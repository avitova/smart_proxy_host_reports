# frozen_string_literal: true

require_relative "friendly_message"

module Proxy::Reports
  class AnsibleProcessor < Processor
    KEYS_TO_COPY = %w[check_mode].freeze

    def initialize(data, json_body: true)
      super(data, json_body: json_body)
      measure :parse do
        @data = JSON.parse(data)
      end
      @body = {}
      @failure = 0
      @change = 0
      @nochange = 0
      logger.debug "Processing report #{report_id}"
      debug_payload("Input", @data)
    end

    def report_id
      @data["uuid"] || generated_report_id
    end

    def count_summary(result)
      if result["result"]["changed"]
        @change += 1
      else
        @nochange += 1
      end
      if result["failed"]
        @failure += 1
      end
    end

    def process_results(facts = true)
      @data["results"]&.each do |result|
        raise("Report do not contain required 'results/result' element") unless result["result"]
        raise("Report do not contain required 'results/task' element") unless result["task"]
        process_level(result)
        process_facts unless facts
        friendly_message = FriendlyMessage.new(result)
        result["friendly_message"] = friendly_message.generate_message
        process_keywords(result)
        count_summary(result)
      end
      @data["results"]
    rescue StandardError => e
      log_error("Unable to parse results", e)
      @data["results"]
    end

    def process(facts = true)
      @body["format"] = "ansible"
      @body["id"] = report_id
      @body["host"] = hostname_from_config || @data["host"]
      @body["proxy"] = Proxy::Reports::Plugin.settings.reported_proxy_hostname
      @body["reported_at"] = @data["reported_at"]
      @body["reported_at_proxy"] = now_utc
      measure :process_results do
        @body["results"] = process_results(facts)
      end
      @body["summary"] = build_summary
      process_root_keywords
      @body["keywords"] = keywords
      @body["telemetry"] = telemetry
      @body["errors"] = errors if errors?
      KEYS_TO_COPY.each do |key|
        @body[key] = @data[key]
      end
    end

    def build_report
      process(false)
      if debug_payload?
        logger.debug { JSON.pretty_generate(@body) }
      end
      build_report_root(
        format: "ansible",
        version: 1,
        host: @body["host"],
        proxy: @body["proxy"],
        change: @body["summary"]["foreman"]["change"],
        nochange: @body["summary"]["foreman"]["nochange"],
        failure: @body["summary"]["foreman"]["failure"],
        keywords: @body["keywords"],
        body: @body,
      )
    end

    def spool_report
      report_hash = build_report
      debug_payload("Output", report_hash)
      payload = measure :format do
        report_hash.to_json
      end
      SpooledHttpClient.instance.spool("report", report_id, payload)
    end

    def find_facts_task
      @data["results"]&.each do |result|
        unless result["result"].nil? && result["result"]["ansible_facts"].nil?
          return result
        end
      end
    end

    def build_facts
      process
      if debug_payload?
        logger.debug { JSON.pretty_generate(@body) }
      end
      facts = find_facts_task
      {
        "name" => @hostname_from_config || @data["host"],
        "facts" => {
          "ansible_facts" => facts,
          "_type" => "ansible",
          "_timestamp" => @data["reported_at"],
        },
      }
    end

    def spool_facts(facts)
      SpooledHttpClient.instance.spool("facts", report_id, facts)
    end

    def process_facts
      spool_facts(build_facts)
    end

    # foreman-ansible-modules 3.0 does not contain summary field, convert it here
    # https://github.com/theforeman/foreman-ansible-modules/pull/1325/files
    def build_summary
      if @data["summary"]
        native = @data["summary"]
      elsif (status = @data["status"])
        native = {
          "changed" => status["applied"] || 0,
          "failures" => status["failed"] || 0,
          "ignored" => 0,
          "ok" => 0,
          "rescued" => 0,
          "skipped" => status["skipped"] || 0,
          "unreachable" => 0,
        }
      else
        native = {}
      end
      {
        "foreman" => {
          "change" => @change, "nochange" => @nochange, "failure" => @failure,
        },
        "native" => native,
      }
    rescue StandardError => e
      log_error("Unable to build summary", e)
      {
        "foreman" => {
          "change" => @change, "nochange" => @nochange, "failure" => @failure,
        },
        "native" => {},
      }
    end

    def process_root_keywords
      if (summary = @body["summary"])
        if summary["changed"] && summary["changed"] > 0
          add_keywords("AnsibleChanged")
        elsif summary["failures"] && summary["failures"] > 0
          add_keywords("AnsibleFailures")
        elsif summary["unreachable"] && summary["unreachable"] > 0
          add_keywords("AnsibleUnreachable")
        elsif summary["rescued"] && summary["rescued"] > 0
          add_keywords("AnsibleRescued")
        elsif summary["ignored"] && summary["ignored"] > 0
          add_keywords("AnsibleIgnored")
        elsif summary["skipped"] && summary["skipped"] > 0
          add_keywords("AnsibleSkipped")
        end
      end
    rescue StandardError => e
      log_error("Unable to parse root summary keywords", e)
    end

  private

    def process_keywords(result)
      if result["failed"]
        add_keywords("AnsibleFailure", "AnsibleFailure:#{result["task"]["action"]}")
      elsif result["result"]["changed"]
        add_keywords("AnsibleChanged")
      end
    rescue StandardError => e
      log_error("Unable to parse keywords", e)
    end

    def process_level(result)
      if result["failed"]
        result["level"] = "err"
      elsif result["result"]["changed"]
        result["level"] = "notice"
      else
        result["level"] = "info"
      end
    rescue StandardError => e
      log_error("Unable to parse log level", e)
      result["level"] = "info"
    end
  end

  def search_for_facts(result)
    if result.respond_to?(:key?) && result.key?(:ansible_facts)
      result[:ansible_facts]
    elsif result.respond_to?(:each)
      r = nil
      result.find{ |*a| r = search_for_facts(a.last) }
      r
    end
  end
end
