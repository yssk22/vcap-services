# Copyright (c) 2009-2012 VMware, Inc.
require "mysql2"
require "timeout"

module Mysql2
  class Client
    class << self
      attr_accessor :default_timeout
      attr_accessor :logger
    end

    alias :origin_initialize :initialize
    alias :origin_query :query

    def initialize(opts={})
      wait_timeout = self.class.default_timeout
      # client side timeout
      opts.merge!({
        :read_timeout => wait_timeout,
        :connect_timeout => wait_timeout,
      }) if wait_timeout
      client = origin_initialize(opts)
      # server side timeout
      client.query("set @@wait_timeout=#{wait_timeout}") if wait_timeout
      client
    end
  end
end
