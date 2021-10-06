require "sinatra"
require "yaml"
require "smart_proxy_host_reports/host_reports"
require "smart_proxy_host_reports/processor"
require "smart_proxy_host_reports/puppet_processor"
require "smart_proxy_host_reports/ansible_processor"

module Proxy::HostReports
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    include ::Proxy::Util
    helpers ::Proxy::Helpers

    before do
      content_type "application/json"
    end

    def check_content_type(format)
      request_type = request.env["CONTENT_TYPE"]
      if format == "puppet"
        log_halt(415, "Content type must be application/x-yaml, was: #{request_type}") unless request_type.start_with?("application/x-yaml")
      elsif format == "ansible"
        log_halt(415, "Content type must be application/json, was: #{request_type}") unless request_type.start_with?("application/json")
      else
        log_halt(415, "Unknown format: #{format}")
      end
    end

    post "/:format" do
      format = params[:format]
      log_halt(404, "Format argument not specified") unless format
      check_content_type(format)
      input = request.body.read
      if Proxy::HostReports::Plugin.settings.incoming_save_dir
        filename = File.join(Proxy::HostReports::Plugin.settings.incoming_save_dir, "#{format}-#{Time.now.to_i}")
        File.open(filename, "w") { |f| f.write(input) }
      end
      log_halt(415, "Missing body") if input.empty?
      json_body = to_bool(params[:json_body], true)
      processor = Processor.new_processor(format, input, json_body: json_body)
      processor.spool_report
    rescue => e
      log_halt 415, e, "Error during report processing: #{e.message}"
    end
  end
end
