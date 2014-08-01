# PubKey agent setup #

##Prerequisites##

First of all, you will need a recent Ruby (1.9.x). 

If you are on any debianish system (Ubuntu / Debian / Raspbian), install it like this:

```
apt-get update
apt-get install -y git build-essential ruby1.9.1 ruby1.9.1-dev rubygems1.9.1 irb1.9.1 ri1.9.1 rdoc1.9.1 wget libxml2-dev libxslt-dev libopenssl-ruby1.9.1 libssl-dev zlib1g-dev

```

If you are on a Redhatish distro (Redhat, Centos, Fedora or Amazon Linux), then:

```

yum update
yum install git-core gcc-c++ patch readline readline-devel zlib zlib-devel ruby ruby-libs ruby-devel ruby-docs ruby-ri ruby-irb ruby-rdoc ruby-mode

```

Then update your ruby gem install and install Bundler:

```
gem update --no-rdoc --no-ri
gem install bundler --no-rdoc --no-ri
```

*Note*: PubKey agent has not been tested with Jruby / RVM - However if you do have those, theres nothing preventing the agent from being run via them.

##Clone the PubKey agent repo & install required gems##

This doc and all the setup scripts assume we install to `/opt/pkagent`.

```

cd /opt && git clone git@github.com:onepowerltd/pkagent.git
cd /opt/pkagent && bundle install

```

##Setup PubKey as a system service ##

You want to ensure PubKey agent starts up at boot time. There are two ways to do this,

* Via an init.d script (Pretty much any Linux distro should have this :-))
* Via an upstart job (Any debianish distro will have this. Also RH EL6 and hence Centos 6 onwards have Upstart)


The advantages to an upstart job is that it can be automatically be respawned if it fails. 

##Run modes##

###Preferred - As a daemon###

This would use `pkagent.rb` - This is a daemon (kind) of process which is always running. It connects to the PubKey messaging system and can be triggered to perform agent runs based on your notifying it from the [PubKey Console](https://www.pubkey.in/console/). It also reports check-in status back to the console so you can list which systems updated. The daemon is quite lightweight and sleeps for most of the time until a user change happens or you trigger it to run.
It wakes up every 30 minutes to poll PubKey API. You can also `touch /etc/pubkey.update` anytime to force an update.

*This is the preferred run mode and is what gets setup with an `init.d` or `upstart` job for PubKey agent.*

Run `./setup.sh` from `/opt/pkagent` to set this up.

###Standalone mode###

You could also run `cd /opt/pkagent && bundle exec ./pkagent-standalone.rb` via a cron job. You want to set this to run every 10 minutes or higher.
(Running the agent more often that this via cron/any-other-mechanism is to be avoided).

This is a handy mode for your local VMs or Raspberry Pis that are'nt always on :-)

##Agent Logging##

The agent logs all its activities to syslog (`INFO`) as `PubKeysAgent`.

##Agent config##

Both `pkagent.rb` and `pkagent-standalone.rb` expect a YAML config `pubkeyagent.yml` to be present in `/opt/pkagent` (Or whichever path you cloned into).

A sample config `pubkeyagent-sample.yml` is provided.
```
---
usertoken: <usertoken>
apikey: <apitoken>
user_blacklist:
- root
user_whitelist:
apihost: https://api.pubkey.in
purge_other_keys: false

```

The only two parameters that are required as `usertoken` and `apikey`. These can be obtained from the Console from the Team admin page (Teams -> Manage AuthKeys).

See [Agent docs](http://docs.pubkey.in/agentsetup) for details on the config parameters.


