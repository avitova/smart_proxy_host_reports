# frozen_string_literal: true

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
    logger.error "Unable to parse logs", e
    logs
  end

  def process_resource_statuses
    statuses = []
    @data["resource_statuses"]&.each_pair do |key, value|
      statuses << key
      @evaluation_times << [key, value["evaluation_time"]]
      # failures
      add_keywords("PuppetResourceFailed:#{key}", "PuppetHasFailure") if value["failed"] || value["failed_to_restart"]
      value["events"]&.each do |event|
        add_keywords("PuppetResourceFailed:#{key}", "PuppetHasFailure") if event["status"] == "failed"
        add_keywords("PuppetHasCorrectiveChange") if event["corrective_change"]
      end
      # changes
      add_keywords("PuppetHasChange") if value["changed"]
      add_keywords("PuppetHasChange") if value["change_count"] && value["change_count"] > 0
      # changes
      add_keywords("PuppetIsOutOfSync") if value["out_of_sync"]
      add_keywords("PuppetIsOutOfSync") if value["out_of_sync_count"] && value["out_of_sync_count"] > 0
      # skips
      add_keywords("PuppetHasSkips") if value["skipped"]
      # corrective changes
      add_keywords("PuppetHasCorrectiveChange") if value["corrective_change"]
    end
    statuses
  rescue StandardError => e
    logger.error "Unable to parse resource_statuses", e
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
    logger.error "Unable to process evaluation_times", e
    []
  end

  def process
    measure :process do
      @body["format"] = "puppet"
      @body["id"] = report_id
      @body["host"] = hostname_from_config || @data["host"]
      @body["proxy"] = Proxy::HostReports::Plugin.settings.reported_proxy_hostname
      @body["reported_at"] = @data["time"]
      KEYS_TO_COPY.each do |key|
        @body[key] = @data[key]
      end
      @body["logs"] = process_logs
      @body["resource_statuses"] = process_resource_statuses
      @body["keywords"] = keywords
      @body["evaluation_times"] = process_evaluation_times
      @body["telemetry"] = telemetry
      @body["errors"] = errors if errors?
    end
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
      reported_at: @body["reported_at"],
      status: 0,
      proxy: @body["proxy"],
      body: @body,
      keywords: @body["keywords"],
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
end
