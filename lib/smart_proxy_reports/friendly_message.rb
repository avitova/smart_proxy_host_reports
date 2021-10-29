class FriendlyMessage
  def initialize(result)
    @result = result
    @result_tree = @result["result"]
    @task_tree = @result["task"]
    @module_args_tree = @result_tree.dig("invocation", "module_args")
  end

  def generate_message
    msg = "N/A"
    return msg if @task_tree.nil? || @task_tree["action"].nil?
    return @result_tree["msg"] if @result["failed"]

    case @task_tree["action"]
    when "ansible.builtin.package", "package" then msg = package_message
    when "ansible.builtin.template", "template" then msg = template_message
    when "ansible.builtin.service", "service" then msg = service_message
    when "ansible.builtin.group", "group" then msg = group_message
    when "ansible.builtin.user", "user" then msg = user_message
    when "ansible.builtin.cron", "cron" then msg = cron_message
    when "ansible.builtin.copy", "copy" then msg = copy_message
    when "ansible.builtin.command", "ansible.builtin.shell", "command", "shell" then msg = @result_tree["stdout_lines"]
    end
    msg
  rescue StandardError => e
    logger.debug "Unable to parse result (#{e.message}): #{@result.inspect}"
    msg
  end

  def human_readable_array(array, length = 10)
    return array if array.nil?
    return array.slice(0, length).join(", ") + " and more" if array.length > length
    array.join(", ")
  end

  def package_message
    packages = human_readable_array(@module_args_tree["name"])
    state = "present"
    state = @module_args_tree["state"] unless @module_args_tree["state"].nil?
    "Package(s) #{packages} are #{state}"
  end

  def template_message
    "Render template #{@module_args_tree["_original_basename"]} to #{@result_tree["dest"]}"
  end

  def service_message
    "Service #{@result_tree["name"]} is #{@result_tree["state"]} and enabled: #{@result_tree["enabled"]}"
  end

  def group_message
    "User group #{@result_tree["name"]} is #{@result_tree["state"]} with gid: #{@result_tree["gid"]}"
  end

  def user_message
    "User #{@result_tree["name"]} is #{@result_tree["state"]} with uid: #{@result_tree["uid"]}"
  end

  def cron_message
    "Cron job: #{@module_args_tree["minute"]} #{@module_args_tree["hour"]} #{@module_args_tree["day"]} #{@module_args_tree["month"]} #{@module_args_tree["weekday"]} #{@module_args_tree["job"]} and disabled: #{@module_args_tree["disabled"]}"
  end

  def copy_message
    "Copy #{@module_args_tree["_original_basename"]} to #{@result_tree["dest"]}"
  end
end
