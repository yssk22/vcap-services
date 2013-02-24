# Copyright (c) 2009-2011 VMware, Inc.
require 'time'
require 'em-http'
require 'json'
require 'json_message'
require 'services/api'
require 'fiber'

module VCAP
  module Services
    module Backup
    end
  end
end

require 'util'

module VCAP::Services::Backup::Worker

  @manager = nil
  @options = {}
  @serv_ins = {}

  include VCAP::Services::Backup::Util

  def run
    if Dir.exists?(@manager.root)
      @manager.logger.info("#{self.class}: Running");
      get_live_service_ins
      scan(@manager.root)
    else
      @manager.logger.warn("Root directory for scanning is not existed.")
    end
    true
  rescue Interrupt
    raise
  rescue Exception => x
    @manager.logger.error("#{self.class}: Exception while running: #{x.message}, #{x.backtrace.join(', ')}")
    false
  end

  def handle_response(http,name)
    instances = []
    if http.response_header.status == 200
      begin
        resp = VCAP::Services::Api::ListHandlesResponse.decode(http.response)
        resp.handles.each do |h|
          if h['service_id']
            service_id = h['service_id']
            #Because some old service_ids may initial with service name,
            #remove the service name for compatibility's sake.
            service_id.gsub!(/^(mongodb|redis)-/,'')
            service_id = String.new(service_id)
            instances << service_id if service_id
          end
        end if resp.handles
        @serv_ins[name] = instances
        @manager.logger.debug("Live #{name} instances: #{instances.size}")
      rescue => e
        @manager.logger.error("Error to parse handle: #{e.message}")
      end
    else
      @manager.logger.warn("Fetching #{name} handle ans: #{http.response_header.status}")
    end
  end

  def get_live_service_ins
    cc_uri = @options[:cloud_controller_uri]||"api.vcap.me"
    cc_uri = "http://#{cc_uri}" if !cc_uri.start_with?("http://")
    @serv_ins = {}

    @options[:services].each do |name,svc|
      version = svc['version']
      uri = "#{cc_uri}/services/v1/offerings/#{name}-#{version}/handles"
      REQ_HEADER[:head]['X-VCAP-Service-Token'] = svc['token']||'0xdeadbeef'
      result, http = request_service_ins_fibered(uri)
      if result
        handle_response(http, name)
      else
        @manager.logger.error("Error at fetching handle at #{uri} ans: #{http}")
      end
      raise Interrupt, "Interrupted" if @manager.shutdown?
    end if @options[:services]
  rescue => e
    @manager.logger.error "Failed to get_live_service_ins #{e.message}"
  end

  def prune(path, timestamp=nil )
    if timestamp
      @manager.logger.info("Pruning #{path} from #{Time.at(timestamp)}")
    else
      @manager.logger.info("Pruning #{path} ")
    end
    rmdashr(path)
    # also prune any parent directories that have become empty
    path = parent(path)
    while path != @manager.root && empty(path)
      @manager.logger.info("Pruning empty parent #{path}")
      Dir.delete(path)
      path = parent(path)
    end
  rescue => x
    @manager.logger.error("Could not prune #{path}: #{x.to_s}")
  ensure
    raise Interrupt, "Interrupted" if @manager.shutdown?
  end

end

