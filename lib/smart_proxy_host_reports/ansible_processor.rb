# frozen_string_literal: true

class AnsibleProcessor < Processor
  KEYS_TO_COPY = %w[status check_mode].freeze

  def initialize(data, json_body: true)
    super(data, json_body: json_body)
    measure :parse do
      @data = JSON.parse(data)
    end
    @body = {}
    logger.debug "Processing report #{report_id}"
    debug_payload("Input", @data)
  end

  def report_id
    @data["uuid"] || generated_report_id
  end

  def process_results
    @data["results"]&.each do |result|
      process_level(result)
      process_message(result)
      process_keywords(result)
    end
    @data["results"]
  rescue StandardError => e
    logger.error "Unable to parse results", e
    @data["results"]
  end

  def process
    measure :process do
      @body["format"] = "ansible"
      @body["id"] = report_id
      @body["host"] = hostname_from_config || @data["host"]
      @body["proxy"] = Proxy::HostReports::Plugin.settings.reported_proxy_hostname
      @body["reported_at"] = @data["reported_at"]
      @body["results"] = process_results
      @body["keywords"] = keywords
      @body["telemetry"] = telemetry
      @body["errors"] = errors if errors?
      KEYS_TO_COPY.each do |key|
        @body[key] = @data[key]
      end
    end
  end

  def build_report
    process
    if debug_payload?
      logger.debug { JSON.pretty_generate(@body) }
    end
    build_report_root(
      format: "ansible",
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

  private

  def process_keywords(result)
    if result["failed"]
      add_keywords("HasFailure", "AnsibleTaskFailed:#{result["task"]["action"]}")
    elsif result["result"]["changed"]
      add_keywords("HasChange")
    end
  end

  def process_level(result)
    if result["failed"]
      result["level"] = "err"
    elsif result["result"]["changed"]
      result["level"] = "notice"
    else
      result["level"] = "info"
    end
  end

  def process_message(result)
    msg = "N/A"
    return msg if result["task"].nil? || result["task"]["action"].nil?
    return result["result"]["msg"] if result["failed"]
    result_tree = result["result"]
    task_tree = result["task"]
    raise("Report do not contain required 'results/result' element") unless result_tree
    raise("Report do not contain required 'results/task' element") unless task_tree
    module_args_tree = result_tree.dig("invocation", "module_args")

    case task_tree["action"]
    when "ansible.builtin.package"
      detail = result_tree["results"] || result_tree["msg"] || "No details"
      msg = "Package(s) #{module_args_tree["name"].join(",")} are #{module_args_tree["state"]}: #{detail}"
    when "ansible.builtin.template"
      msg = "Render template #{module_args_tree["_original_basename"]} to #{result_tree["dest"]}"
    when "ansible.builtin.service"
      msg = "Service #{result_tree["name"]} is #{result_tree["state"]} and enabled: #{result_tree["enabled"]}"
    when "ansible.builtin.group"
      msg = "User group #{result_tree["name"]} is #{result_tree["state"]} with gid: #{result_tree["gid"]}"
    when "ansible.builtin.user"
      msg = "User #{result_tree["name"]} is #{result_tree["state"]} with uid: #{result_tree["uid"]}"
    when "ansible.builtin.cron"
      msg = "Cron job: #{module_args_tree["minute"]} #{module_args_tree["hour"]} #{module_args_tree["day"]} #{module_args_tree["month"]} #{module_args_tree["weekday"]} #{module_args_tree["job"]} and disabled: #{module_args_tree["disabled"]}"
    when "ansible.builtin.copy"
      msg = "Copy #{module_args_tree["_original_basename"]} to #{result_tree["dest"]}"
    when "command", "shell"
      msg = result_tree["stdout_lines"]
    end
  rescue StandardError => e
    logger.debug "Unable to parse result (#{e.message}): #{result.inspect}"
  ensure
    result["friendly_message"] = msg
  end
end
