require "rack/test"
require "test/unit"
require "mocha/test_unit"
require "json-diff"
require "webmock/test_unit"
require "smart_proxy_for_testing"
require "smart_proxy_reports"
require "smart_proxy_reports/reports"
require "smart_proxy_reports/reports_api"
require "smart_proxy_reports/processor"
require "smart_proxy_reports/puppet_processor"
require "smart_proxy_reports/spooled_http_client"

LOG = "/tmp/proxy-test.log"
FileUtils.rm_f(LOG) if File.exist?(LOG)
::Proxy::SETTINGS.log_file = LOG

ENV["RACK_ENV"] = "test"
ENV["TESTOPTS"] = "--verbose"

def check_hash_keys(hoa)
  hoa.each do |k, v|
    raise("Key '#{k}' is not string") if hoa.is_a?(Hash) && !k.is_a?(String)
    if v&.is_a?(Hash) || v&.is_a?(Array)
      check_hash_keys(v)
    elsif k.is_a?(Array)
      check_hash_keys(k)
    end
  end
  true
end

def setup_processor(type, filename)
  input = File.read(File.join(File.dirname(__FILE__), "fixtures/#{filename}"))
  ::Proxy::Reports::Processor.new_processor(type, input, json_body: false)
end

def assert_snapshot(result, snapshot_filename)
  unless File.exist? snapshot_filename
    File.write(snapshot_filename, JSON.pretty_generate(result))
  end
  diff_result = ::JsonDiff.diff(JSON.parse(File.read(snapshot_filename), quirks_mode: true), result)
  unless diff_result.empty?
    fail "\nError in JSON diff for #{snapshot_filename}, review and delete it to generate:\n#{JSON.pretty_generate(diff_result)}\n"
  end
end

def remove_volatile_keys(result)
  result["host_report"]["reported_at"] = ""
  result["host_report"]["body"]["reported_at"] = ""
  result["host_report"]["body"]["reported_at_proxy"] = ""
  result["host_report"]["body"]["id"] = ""
  result["host_report"]["body"]["telemetry"] = {}
end
