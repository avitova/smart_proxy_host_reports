require "test_helper"
require "lib/smart_proxy_reports/friendly_message"

class FriendlyMessageTest < Test::Unit::TestCase
  def setup
    information = { "result" => {
      "invocation" => {
        "module_args" => {},
      },
    } }
    @friendly_instance = FriendlyMessage.new(information)
  end

  def test_human_readable_array_empty
    assert @friendly_instance.human_readable_array([]) == ""
  end

  def test_human_readable_array_nil
    assert @friendly_instance.human_readable_array(nil).nil?
  end

  def test_human_readable_array_normal
    assert @friendly_instance.human_readable_array(["vim", "git", "package", "package2"]) == "vim, git, package, package2"
  end

  def test_long_human_readable_array_long
    packages = ["pack1", "pack2", "pack3", "pack4", "pack5", "pack6", "pack7", "pack8", "pack9", "pack10", "pack11", "pack12"]
    expected = "pack1, pack2, pack3, pack4, pack5, pack6, pack7, pack8, pack9, pack10 and more"
    assert @friendly_instance.human_readable_array(packages) == expected
  end
end
