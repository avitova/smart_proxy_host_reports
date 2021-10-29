require "test_helper"

class AnsibleProcessorTest < Test::Unit::TestCase
  def setup
    Proxy::Reports::Plugin.settings.stubs(:reported_proxy_hostname).returns("localhost")
  end

  def test_keys_are_strings
    processor = setup_processor("ansible", "ansible-copy-nochange.json")
    report = processor.build_report
    facts = processor.build_facts
    assert check_hash_keys(report), "All keys are strings: #{report.inspect}"
    assert check_hash_keys(facts), "All keys are strings: #{facts.inspect}"
  end

  Dir.glob(File.join(File.dirname(__FILE__), "fixtures", "ansible*json")).each do |fixture_filename|
    fixture_filename = File.basename(fixture_filename.tr("- ", "--"))
    define_method("test_snapshot_#{fixture_filename}") do
      processor = setup_processor("ansible", fixture_filename)
      result_report = processor.build_report
      result_facts = processor.build_facts
      remove_volatile_keys(result_report)
      snapshot_filename_r = File.join(File.dirname(__FILE__), "snapshots", "#{File.basename(fixture_filename)}.report.snapshot.json")
      snapshot_filename_f = File.join(File.dirname(__FILE__), "snapshots", "#{File.basename(fixture_filename)}.facts.snapshot.json")
      assert_snapshot(result_report, snapshot_filename_r)
      assert_snapshot(result_facts, snapshot_filename_f)
    end
  end
end
