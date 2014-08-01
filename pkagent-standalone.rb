#!/usr/bin/ruby
require 'bundler'
Bundler.require
require "socket"
require "yaml"

$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "core.rb"
Cfg = File.dirname(__FILE__)+'/pubkeyagent.yml'
abort "PubKey agent needs to run as root" unless Process.uid==0
include PubKeys::Agent

runner = PubKeys::Agent::Runner.new(Cfg)

status = runner.run
ct = status['changed'].length > 0 ? "Modified #{status['changed'].length} users, (#{status['changed'].join(",")})" : "None"
logmsg("Changed #{ct} on #{status['hostname']}")
