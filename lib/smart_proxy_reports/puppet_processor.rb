# frozen_string_literal: true

module Proxy::Reports
  class PuppetProcessor < Processor
    YAML_CLEAN = /!ruby\/object.*$/.freeze
    KEYS_TO_COPY = %w[report_format puppet_version environment metrics].freeze
    MAX_EVAL_TIMES = 29

    def initialize(data, json_body: true)
      super(data, json_body: json_body)
      measure :parse do
        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.6.0")
          # Ruby 2.5 or older does not have permitted_classes argument available
          @data = YAML.load(data.gsub(YAML_CLEAN, ""))
        else
          @data = YAML.safe_load(data.gsub(YAML_CLEAN, ""), permitted_classes: [Symbol, Time, Date])
        end
      end
      raise("No content") unless @data
      @body = {}
      @evaluation_times = []
      logger.debug "Processing report #{report_id}"
      debug_payload("Input", @data)
    end

    def report_id
      @data["transaction_uuid"] || generated_report_id
    end

    def process_logs
      logs = []
      @data["logs"]&.each do |log|
        logs << [log["level"]&.to_s, log["source"], log["message"]]
      end
      logs
    rescue StandardError => e
      log_error("Unable to parse logs", e)
      logs
    end

    def process_root_keywords
      status = @data["status"]
      if status == "changed"
        add_keywords("PuppetStatusChanged")
      elsif status == "unchanged"
        add_keywords("PuppetStatusUnchanged")
      elsif status == "failed"
        add_keywords("PuppetStatusFailed")
      end
      if @data["noop"] == "true"
        add_keywords("PuppetNoop")
      end
      if @data["noop_pending"] == "true"
        add_keywords("PuppetNoopPending")
      end
    rescue StandardError => e
      log_error("Unable to parse root keywords", e)
    end

    def process_resource_statuses
      statuses = []
      @data["resource_statuses"]&.each_pair do |key, value|
        statuses << key
        @evaluation_times << [key, value["evaluation_time"]]
        add_keywords("PuppetFailed:#{key}", "PuppetFailed") if value["failed"]
        add_keywords("PuppetFailedToRestart:#{key}", "PuppetFailedToRestart") if value["failed_to_restart"]
        add_keywords("PuppetCorrectiveChange") if value["corrective_change"]
        add_keywords("PuppetSkipped") if value["skipped"]
        add_keywords("PuppetRestarted") if value["restarted"]
        add_keywords("PuppetScheduled") if value["scheduled"]
        add_keywords("PuppetOutOfSync") if value["out_of_sync"]
        add_keywords("PuppetEnvironment:#{@data["environment"]}") if @data["environment"]
      end
      statuses
    rescue StandardError => e
      log_error("Unable to parse resource_statuses", e)
      statuses
    end

    def process_evaluation_times
      @evaluation_times.sort! { |a, b| b[1] <=> a[1] }
      if @evaluation_times.count > MAX_EVAL_TIMES
        others = @evaluation_times[MAX_EVAL_TIMES..@evaluation_times.count - 1].sum { |x| x[1] }
        @evaluation_times = @evaluation_times[0..MAX_EVAL_TIMES - 1]
        @evaluation_times << ["Others", others] if others > 0.0001
      end
      @evaluation_times
    rescue StandardError => e
      log_error("Unable to parse evaluation_times", e)
      []
    end

    def process
      @body["format"] = "puppet"
      @body["id"] = report_id
      @body["host"] = hostname_from_config || @data["host"]
      @body["proxy"] = Proxy::Reports::Plugin.settings.reported_proxy_hostname
      @body["reported_at"] = @data["time"]
      @body["reported_at_proxy"] = now_utc
      KEYS_TO_COPY.each do |key|
        @body[key] = @data[key]
      end
      process_root_keywords
      measure :process_logs do
        @body["logs"] = process_logs
      end
      measure :process_resource_statuses do
        @body["resource_statuses"] = process_resource_statuses
      end
      measure :process_summary do
        @body["summary"] = process_summary
      end
      measure :process_evaluation_times do
        @body["evaluation_times"] = process_evaluation_times
      end
      @body["telemetry"] = telemetry
      @body["keywords"] = keywords
      @body["errors"] = errors if errors?
    end

    def build_report
      process
      if debug_payload?
        logger.debug { JSON.pretty_generate(@body) }
      end
      build_report_root(
        format: "puppet",
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
      SpooledHttpClient.instance.spool(report_id, payload)
    end

    private

    def process_summary
      events = @body["metrics"]["events"]["values"].collect { |s| [s[0], s[2]] }.to_h
      resources = @body["metrics"]["resources"]["values"].collect { |s| [s[0], s[2]] }.to_h
      {
        "foreman" => {
          "change" => events["success"],
          "nochange" => resources["total"] - events["failure"] - events["success"],
          "failure" => events["failure"],
        },
        "native" => resources,
      }
    rescue StandardError => e
      log_error("Unable to parse summary counts", e)
      {
        "foreman" => {
          "change" => 0,
          "nochange" => 0,
          "failure" => 0,
        },
        "native" => {},
      }
    end
  end
end
