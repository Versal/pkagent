#!/usr/bin/ruby
module PubKeys

  module Observable
    attr_accessor :state

    def add_observer(obr)
      @observers ||=[]
      @observers << obr unless @observers.include?(obr)
    end

    def del_observer(obr)
      @observers.del(obr)
    end

    def state=(st)
      @state=st
      if !@observers.nil?
        @observers.each {|ox| ox.watcherupdate(@state) }
      end
    end

  end #ends observable

  module Watcher

    def watcherupdate(obrstate)
      #Implement in class.
    end

  end #ends watcher

end
