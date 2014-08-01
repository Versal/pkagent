#!/usr/bin/ruby
require 'bundler'
Bundler.require
require "socket"
require "yaml"
require "json"
require "socket"

$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "core.rb"
require "connection.rb"
Cfg=File.dirname(__FILE__)+'/pubkeyagent.yml'
abort 'PubKey agent needs to run as root' unless Process.uid==0

include PubKeys::Agent

EM.run{
  pk=EM.connect(PubKeys::Agent::STOMP[:host], PubKeys::Agent::STOMP[:port], PubkeyStomper, {:auto_reconnect => true, :timeout => 5})
  runner=PubKeys::Agent::Runner.new(Cfg)
  pk.agent=runner
  pk.comm_inactivity_timeout=300
  runner.add_observer(pk)

  #In real life, data fetched by agent is cached on PubKey api servers for upto 24 hours and updated only when user/admin modifies it.
  #So run() frequently is sort of pointless.
  #Ideally, "team admin" could force an update from his console when updating a team
  EventMachine::PeriodicTimer.new((ENV['DEBUG']? 300: 1800)) do
    runner.run
  end
  #OR
  #For users with a large stack of servers, just "touch /etc/pubkey.update" to force run within a minute
  EventMachine::PeriodicTimer.new((ENV['DEBUG']? 10: 60)) do
    runner.run if File.exists?(FORCEUPD)
  end

  reaper = Proc.new { logmsg("Exiting!"); EM.stop  }
  Signal.trap "TERM", reaper
  Signal.trap "INT", reaper
}
