#!/usr/bin/ruby

require "json"
require "faraday"
require "uri"
require "syslog"
require "etc"
require "sshkey"
require 'digest/md5'
require "securerandom"
require "monitor"

$LOAD_PATH.unshift(File.dirname(__FILE__)+'../lib')
require "observe.rb"

#Pubkey api caches responses server side for upto 24 hours. They change only when underlying data changes (e.g. keys/users/teams added/removed etc).
# So hitting api frequently is pointless. Agent can be triggered to "run" whenever update happens via web console.
module PubKeys
  module Agent

    Timeformat='%Y%m%d.%H:%M:%S'
    THISHOST=Socket.gethostname

    def logmsg(msg,syslogtoo=true)
      if !msg.nil?
        $stderr.puts "#{Time.now.strftime(Timeformat)} [PID #{$$.to_i}] - #{msg}" unless msg.nil?
        Syslog.open('PubKeysAgent', Syslog::LOG_PID, Syslog::LOG_SYSLOG) { |s| s.info msg } if syslogtoo
      end
    end

    def randomkey
      Digest::MD5.hexdigest(SecureRandom.urlsafe_base64(32))
    end

    FORCEUPD="/etc/pubkey.update"
    STOMP={
      :host => (ENV.has_key?('STOMPHOST') && ENV['STOMPHOST'] ? ENV['STOMPHOST'] : 'messaging.pubkey.in'),
      :port => 443
    }

    class Runner
      include MonitorMixin
      include PubKeys::Observable
      attr_reader :messaging, :sysinfo, :latestupdate, :billingerror

      def initialize(cfg=nil)
        @cfgfile=cfg
        @config=Hash.new
        @apikey=nil
        @debug=ENV['DEBUG'] ? true: false
        @latestupdate=Time.now.to_i
        @uchanged=[]
        loadconfig
        super() #Since we included MonitorMixin
      end

      #Reload config e.g. when HUP'ped
      def reload
        loadconfig
      end

      def getconn(endpoint)
        uri=(endpoint=~/^\//) ? URI(@config['apihost']+endpoint) : URI(@config['apihost']+'/'+endpoint)
        hostonly="#{uri.scheme}://#{uri.host}:#{uri.port}"
        conn = Faraday.new(:url => hostonly, :ssl => {:verify => !ENV['NOVERIFYSSL']} ) do |faraday|
          faraday.request :url_encoded
					#While normally we would'nt use net/http with EM - Its ok in this case since the request run api is mutex blocked anyway.
          faraday.adapter Faraday.default_adapter
        end
        conn.headers[:user_agent]="PKagent|#{RUBY_VERSION}|#{RUBY_PLATFORM}"
        conn.headers['PKUSERTOKEN']=@usertoken
        conn.headers['PKAPIKEY']=@apikey
        conn.headers['PKAGENTHOST']=THISHOST
        conn
      end

      def run
        r=Hash.new
        self.synchronize do
          keymap=getkeys
          if keymap.nil?
            logmsg("Bad response from web service... Next time maybe.")
            return @sysinfo.merge({"err"=>"Could not contact web service!"})
          end
          puts JSON.pretty_generate(keymap) if @debug
          @uchanged=[]
          keymap.keys.each do |thisuser|
            if processUser(thisuser,keymap[thisuser][:authkey],keymap[thisuser][:keys],keymap[thisuser][:fp], keymap[thisuser][:email])
              logmsg("Modified user #{thisuser}'s authorized keys file #{keymap[thisuser][:authkey]}")
              @uchanged << thisuser
            end
          end
          @latestupdate=Time.now.to_i if @uchanged.length>0
          logmsg("Wrapped up this run.")
          File.unlink(FORCEUPD) if File.exists?(FORCEUPD)
          r=@sysinfo.merge({'changed'=> @uchanged, 'latestupdate'=>@latestupdate})
          self.state=r
        end #end of synced run
        return r
      end

      private

      def getApi(endpoint)
        conn=getconn(endpoint)
        begin
          response=conn.get do |req|
            req.url endpoint
            req.headers['Content-Type'] = 'application/json'
          end
          logmsg("GET #{endpoint}, Status: #{response.status}",false) if @debug
          if response.status==401
            @billingerror=response.headers["x-pk-billing"]
            return '{}'
          elsif response.status==200
            @billingerror=""
            return response.body
          else
            return nil
          end
        rescue Faraday::ConnectionFailed => e
          logmsg("Failed to connect to webservice - #{e.message}")
          return nil
        end
      end

      def postApi(endpoint, data)
        conn=getconn(endpoint)
        begin
          response=conn.post do |req|
            req.url endpoint
            req.headers['Content-Type'] = 'application/json'
            req.body=data
          end
          logmsg("POST #{endpoint}, Status: #{response.status}",false) if @debug
          return (response.status==200 ? response.body : nil)
        rescue Faraday::ConnectionFailed => e
          logmsg("Failed to connect to webservice - #{e.message}")
        end
      end

      def getkeys
        #Get list of known users (in this team)
        ulist=getApi('/api/users') #json
        if ulist.nil? || ulist.empty?
          logmsg("Got NULL from webservice!")
          return nil
        end
        logmsg("Team has users: #{ulist}") if @debug
        #Weed out users that are not on this system and/or blacklisted by admin in config.
        uhash=Hash.new
        JSON.parse(ulist).each_pair do |thisuser,thisemail|
          next if @config['user_blacklist'].include?(thisuser)
          y=ifValidUser(thisuser)
          if y.nil?
            logmsg("Team has #{thisuser} but no such user on this system.")
          else
            if File.directory?(y.dir)
              uhash[thisuser]=[y.dir, thisemail]
            else
              logmsg("Missing homedir #{y.dir} for user #{thisuser} - NOP")
            end
          end
        end
        #Now fetch keys for users in uhash
        allkeys=postApi("/api/users/keys", uhash.keys.to_json)
        if allkeys.nil?
          logmsg("Got NULL from webservice!")
          return nil
        end
        logmsg("Fetched keys for users #{uhash.keys.to_json}")

        keyset=JSON.parse(allkeys) #e.g. user => [ array-of-keys, array-of-fingerprints ]
        #if user was deactivated, array-of-keys will be empty.
        keyobj=Hash.new
        keyset.keys.each do |u|
          homedir, email =uhash[u]
          authkey=@config['authkeyspath'].dup.gsub('$HOME$',homedir).gsub('$USER$',u)
          #puts "User: #{u} #{homedir} AuthKeys=#{authkey}"
          #puts keyset[u].join("\n")
          keyobj[u]={:keys=>keyset[u][0],:fp => keyset[u][1], :email => email, :authkey => @config['authkeyspath'].dup.gsub('$HOME$',homedir).gsub('$USER$',u) }
        end
        return keyobj
      end

      #True on /any/ change to users authorized_keys file.
      def processUser(u=nil,authkeyfile="",keys=Array.new,fplist=Array.new,email="")
        return false if u.nil? || u.empty?
        if keys.length==0
          if @config['purge_other_keys']
            File.unlink(authkeyfile) if File.exists?(authkeyfile)
            logmsg("User #{u}: Dropping #{authkeyfile} since admin set purge_other_keys. No keys on file")
            return true
          end
        end

        origmd5=File.exists?(authkeyfile) ? Digest::MD5.file(authkeyfile).hexdigest : ""
        newcontents=buildAuthKey(authkeyfile, keys, fplist, email)
        newmd5=Digest::MD5.hexdigest(newcontents)
        if origmd5!=newmd5
          tmpfile="/tmp/pk#{u}.$$"
          if writeToAuthKeys(u, tmpfile, newcontents)
						bdir=File.dirname(authkeyfile) #New instance, user has never logged in before?
						if !File.directory?(bdir)
							return false unless bdir=~/^\/home/
							Dir.mkdir(bdir) && FileUtils.chown(u,u,bdir) && File.chmod(0700,bdir) 
						end						
            FileUtils.mv(tmpfile, authkeyfile)
            setPerms(authkeyfile, u)
            return true
          else
            return false
          end
        else
          return false
        end
      end

      def buildAuthKey(fname, keylist, fplist, email)
        keyfpin=Hash.new
        if keylist.length==0
          keyfpin=Hash[ fplist.map { |x| [x,"-"] } ] #This means trash the key from local authorized keys.
        else
					keylist.length.times do |i|
						thisfp=fplist[i]
						keyfpin[thisfp]=keylist[i]	
					end
          #keyfpin=Hash[ keylist.map { |x| [ SSHKey.fingerprint(x), x ] } ]
        end

        if !File.exists?(fname) #No authorized_keys file present yet. easy.
          lines=Array.new
          keyfpin.keys.each do |fp|
            lines << "#Key FP #{fp} via pubkey user #{email} at #{Time.now.to_s}"
            lines << keyfpin[fp]
          end
          return lines.join("\n")+"\n"
        end
        origmd5=Digest::MD5.file(fname).hexdigest

        newlines=Array.new
        IO.read(fname).split("\n").each do |thisline|
          if thisline=~/^#/
            newlines << thisline
          else #If not a comment, then definitely a ssh key.
            thisfp=SSHKey.fingerprint(thisline)
            if keyfpin.has_key?(thisfp)
              if keyfpin[thisfp]=="-"
                newlines << "#Disabled key FP #{thisfp} at #{Time.now.to_s}"
              else
                newlines << keyfpin[thisfp]
              end
              keyfpin.delete(thisfp)
            else
              if @config['purge_other_keys'] #Root says allow no keys except from those from pubkey.
                newlines << "#Disabled key #{thisfp} at #{Time.now.to_s}"
                newlines << '#'+thisline
              else
                newlines << thisline
              end
            end
          end
        end
        keyfpin.keys.each do |fp|
          next if keyfpin[fp]=="-"
          newlines << "#Key FP #{fp} via pubkey user #{email} at #{Time.now.to_s}"
          newlines << keyfpin[fp]
        end
        return newlines.join("\n")+"\n"
      end

      def writeToAuthKeys(user,fname,contents)
        begin
          File.open(fname,"w") {|fh| fh.write(contents) }
          setPerms(fname, user)
          return true
        rescue Exception => e
          logmsg("Could not write to #{fname}")
          return true
        end
      end

      def setPerms(fname,owner)
        return unless File.exists?(fname)
        FileUtils.chown owner, owner, fname
        File.chmod(0600, fname)
      end

      def loadconfig
        begin
          @config=YAML::load(File.open(@cfgfile))
        rescue Exception => e
          abort "Could not read/load config from #{@cfgfile} - #{e.inspect}"
        ensure
          #Need these.
          abort "Missing API Key!" unless @config.has_key?('apikey') && !@config['apikey'].empty?
          @apikey=@config.delete('apikey')
          @usertoken=@config.delete('usertoken')
          #We will not add/manage-keys for users in blacklist
          @config['user_blacklist']=@config.has_key?('user_blacklist') && @config['user_blacklist'].is_a?(Array) ? @config['user_blacklist']: []
          #Always add known system users to blacklist - admin can explictly allow them if needed in whitelist
          %w{root bin daemon adm lp sync shutdown halt operator nobody sshd}.each do |blkduser|
            @config['user_blacklist'] << blkduser unless @config['user_blacklist'].include?(blkduser)
          end
          #Users in whitelist override blacklist - After all, root knows what hes doing.
          @config['user_whitelist']=@config.has_key?('user_whitelist') && @config.is_a?(Array) ?  @config['user_whitelist']: []
          @config['user_blacklist']-=@config['user_whitelist']
          @config['apihost']="https://api.pubkey.in" unless @config.has_key?('apihost')
          #If specified, authkeyspath must have a %h/%u somewhere to be able to individualize paths per users keys.
          @config['authkeyspath']=authkeysPath unless @config.has_key?('authkeyspath')
          #If purge_other_keys is set to true, we will restrict auth keys to contain keys that came in from PubKeys alone.
          @config['purge_other_keys']=@config.has_key?('purge_other_keys') && ifBoolean(@config['purge_other_keys']) ? @config['purge_other_keys'] : false
          logmsg("API Host #{@config['apihost']} - PurgeOtherKeys?=#{@config['purge_other_keys'] ? 'Yes': 'No'} AuthorizedKeysPath=#{@config['authkeyspath']}")
          #If user is on a paid plan and beyond grace time, api will always 401 the agent.
          @sysinfo=getSysinfo #getfromOhai #We could post this to let Org/team owner know the systems that check in... chef does :)
          msgstr=getApi('/api/messaging')
          @messaging=msgstr.nil? ? {}: JSON.parse(msgstr)
          if @messaging.keys.length==0
            logmsg("Error: #{@billingerror}")
            abort "Aborting due to error - #{@billingerror}"
          end
        end
      end

      def ifBoolean(x)
        x.is_a?(TrueClass) || x.is_a?(FalseClass)
      end

      def authkeysPath(sshdconfig='/etc/ssh/sshd_config')
        #Look for AuthorizedKeysFile in config, if empty then defaults to $HOME$/.ssh/authorized_keys
        akloc=`grep ^AuthorizedKeysFile #{sshdconfig} 2>/dev/null`
        if akloc.empty? || akloc=~/^\s*$/
          return '$HOME$/.ssh/authorized_keys'
        else
          return akloc.split(/\s+/)[-1].gsub('%h','$HOME$').gsub('%u','$USER$')
        end
      end

      def ifValidUser(u=nil)
        nil if u.nil?
        uu=nil
        begin
          uu=Etc.getpwnam(u)
        rescue ArgumentError => e
          logmsg("User #{u} not present - #{e.message}")
          uu=nil
        ensure
          return uu
        end
      end

      def getSysinfo
        sysinfo={'hostname'=>Socket.gethostname}
        #More for later.
        return sysinfo
      end
    end #End of class Runner.

  end #eom
end #eom
