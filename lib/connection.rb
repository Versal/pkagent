#!/usr/bin/ruby
require "eventmachine"

$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "core.rb"
require "observe.rb"
include PubKeys::Agent

class PubkeyStomper < EM::Connection
  include EM::Protocols::Stomp
  include PubKeys::Watcher
  attr_accessor :agent

  def initialize(paramshash={})
    @options = {:auto_reconnect => true, :timeout => 3}.merge!(paramshash)
    @connected=false
    @stomp_host=STOMP[:host]
    @stomp_port=STOMP[:port]
    @mykey=randomkey
    @katimer=nil
  end

  def getconf
    @uinfo=@agent.messaging
    @stomphost, @port = @uinfo["stompurl"].split(":")
    @vhost=@uinfo["vhost"]
    @dest="/topic/"+@uinfo["resource"]
  end

  def connection_completed
    getconf
    start_tls
    #This :host here is the virtual host name and not a hostname/ip!
    connect :host => @uinfo["vhost"], :login => @uinfo["user"], :passcode => @uinfo["passwd"], :heartbeat => '50000,50000'
    @connected=true
    logmsg("Connected to #{@stomp_host}:#{@stomp_port}")
  end

  def unbind
    @connected=false
    if !@katimer.nil?
      @katimer.cancel
      @katimer=nil
      logmsg("Cancelled kaapalive timer") if @debug
    end
    logmsg("Disconnected from #{@stomp_host}!")

    EM.add_timer(@options[:timeout]) do
      logmsg("Reconnecting to #{@stomp_host}...")
      reconnect @stomp_host, @stomp_port
    end
  end

  def publish(hash={})
    if hash.keys.length==0 || !hash.has_key?('cmd') || !@connected
      logmsg("Not posting #{hash.inspect}")
    else
      send(@dest, @agent.sysinfo.merge(hash).merge({'at'=>Time.now.to_i, 'sig'=>@mykey}).to_json)
    end
  end

  def receive_msg(msg)
    if msg.command == "CONNECTED"
      logmsg("Subscribing to #{@dest}") if @debug
      subscribe @dest
      publish({'cmd'=>'STARTUP'})
      #Setup keepalive timer to force ELB not to close conn.
      @katimer=EventMachine::PeriodicTimer.new(55) do
        logmsg("KA-timer woke up. Stomp conn idle for last #{@connected ? get_idle_time.round(0): 0}") if @debug
        send @dest, "" if @connected
      end
    else
      return if msg.body.empty?
      logmsg("RawMsg: #{msg.body}",false) if ENV['DEBUG']
      return if msg.body.empty?
      begin
        obj=JSON.parse(msg.body)
      rescue Exception => e
        logmsg("Bad data - not json - #{e.inspect}",false)
        return
      end
      processEvent(obj) if !(obj.has_key?('sig') && obj['sig']==@mykey)
    end
  end

  def processEvent(obj=Hash.new)
    logmsg("Received [#{obj["cmd"]}]") #if obj.has_key?('sig') && obj['sig']!=@mykey
    case obj["cmd"]
    when "PING"
      publish({'cmd'=>'PONG'})
    when 'PONG'
    when 'RUNSTATUS'
    when 'STARTUP'
    when 'UPDATE'
      status=@agent.run
      #publish(status.merge({'cmd'=>'RUNSTATUS'})	) #agent.run will use its observers to eventually call watcherupdate()
    else
      logmsg("Unknown #{obj["cmd"]}") if ENV['DEBUG']
    end	#end case
  end

  #Callback for observable - acts on 'r' sent by runner.
  def watcherupdate(r=nil)
    logmsg("Notified: #{r.to_json}")
    publish( r.merge({'cmd'=>'RUNSTATUS'}) ) if !r.nil? && r.keys.length>0
  end

end

