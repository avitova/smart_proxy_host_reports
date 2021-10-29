# frozen_string_literal: true
require "pp"
require "proxy/log"

module Proxy::Reports
  class Processor
    include ::Proxy::Log

    def self.new_processor(format, data, json_body: true)
      case format
      when "puppet"
        PuppetProcessor.new(data, json_body: json_body)
      when "ansible"
        AnsibleProcessor.new(data, json_body: json_body)
      else
        NotImplementedError.new
      end
    end

    def initialize(*, json_body: true)
      @keywords_set = {}
      @errors = []
      @json_body = json_body
    end

    def generated_report_id
      @generated_report_id ||= SecureRandom.uuid
    end

    def hostname_from_config
      @hostname_from_config ||= Proxy::Reports::Plugin.settings.override_hostname
    end

    def now_utc
      # make sure it contains TZ info: "2022-01-20 14:16:26 UTC"
      Time.now.utc.to_s
    end

    def build_report_root(format:, version:, host:, proxy:, change:, nochange:, failure:, body:, keywords:)
      {
        "host_report" => {
          "format" => format,
          "version" => version,
          "host" => host,
          "reported_at" => now_utc,
          "proxy" => proxy,
          "body" => @json_body ? body.to_json : body,
          "keywords" => keywords,
          "change" => change,
          "nochange" => nochange,
          "failure" => failure,
        },
      }
    end

    def debug_payload?
      Proxy::Reports::Plugin.settings.debug_payload
    end

    def debug_payload(prefix, data)
      return unless debug_payload?
      logger.debug { "#{prefix}: #{data.pretty_inspect}" }
    end

    def add_keywords(*keywords)
      keywords.each do |keyword|
        @keywords_set[keyword] = true
      end
    end

    def keywords
      @keywords_set.keys.to_a rescue []
    end

    attr_reader :errors

    def log_error(message, exception = nil)
      msg = if exception
          "#{message}: #{exception}"
        else
          message
        end
      logger.error msg, exception
      @errors << msg.to_s
    end

    def errors?
      @errors&.any?
    end

    # TODO support multiple metrics and adding total time
    attr_reader :telemetry

    def measure(metric)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @telemetry ||= {}
      @telemetry[metric.to_s] = (t2 - t1) * 1000
    end

    def telemetry_as_string
      result = []
      telemetry.each do |key, value|
        result << "#{key}=#{value.round(1)}ms"
      end
      result.join(", ")
    end

    def spool_report
      super
      logger.debug "Spooled #{report_id}: #{telemetry_as_string}"
    end
  end
end
