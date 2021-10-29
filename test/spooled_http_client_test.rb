require "test_helper"

class SpooledHttpClientTest < Test::Unit::TestCase
  def setup
    @foreman_url = "http://foreman.example.com"
    ::Proxy::SETTINGS.stubs(:foreman_url).returns(@foreman_url)
    ::Proxy::Reports::Plugin.settings.stubs(:keep_reports).returns(true)
    Proxy::Reports::SpooledHttpClient.any_instance.stubs(:time_padding).returns("time")
    @tmpdir = Dir.mktmpdir("spool-http-client-test")
    @client = ::Proxy::Reports::SpooledHttpClient.instance.initialize_directory(@tmpdir)
    
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  def print_spool
    Dir.glob("#{@tmpdir}/**/*") do |file|
      puts file
    end
  end

  def assert_spool(state, filename, contents = nil)
    file = File.join(@tmpdir, state, filename)
    return false unless File.exist? file
    return false if contents && contents != File.read(file)
    true
  end

  def test_spool_plain
    @client.spool("report", "uuid", "something")
    assert assert_spool("todo", "time-report-uuid", "something")
  end

  def test_move_plain
    @client.spool("report", "uuid", "something")
    @client.spool_move("todo", "done", "time-report-uuid")
    assert assert_spool("done", "time-report-uuid")
  end

  def test_process_plain
    stub_request(:post, @foreman_url + "/api/v2/host_reports").with(:body => "body").to_return(:status => [200, "OK"], :body => "body")
    @client.spool("report", "uuid", "body")
    @client.process
    assert assert_spool("done", "time-report-uuid")
  end

  def test_process_plain_two
    stub_request(:post, @foreman_url + "/api/v2/host_reports").with(:body => "body").to_return(:status => [200, "OK"], :body => "body")
    @client.spool("report", "uuid1", "body")
    @client.spool("report", "uuid2", "body")
    @client.process
    assert assert_spool("done", "time-report-uuid1")
    assert assert_spool("done", "time-report-uuid2")
  end

  def test_process_plain_facts
    stub_request(:post, @foreman_url + "/api/v2/hosts/facts").with(:body => "body").to_return(:status => [200, "OK"], :body => "body")
    @client.spool("facts", "uuid", "body")
    @client.process
    assert assert_spool("done", "time-facts-uuid")
  end

  def test_process_plain_two_facts
    stub_request(:post, @foreman_url + "/api/v2/hosts/facts").with(:body => "body").to_return(:status => [200, "OK"], :body => "body")
    @client.spool("facts", "uuid1", "body")
    @client.spool("facts", "uuid2", "body")
    @client.process
    assert assert_spool("done", "time-facts-uuid1")
    assert assert_spool("done", "time-facts-uuid2")
  end
end
