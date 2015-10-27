require 'test/unit'
require 'yaml'
require 'smsnotify/configparser'


class MyTest < Test::Unit::TestCase

  # Called before every test method runs. Can be used
  # to set up fixture information.
  def setup
    # Do nothing
  end

  # Called after every test method runs. Can be used to tear
  # down fixture information.

  def teardown
    # Do nothing
  end

  # Fake test
  def test_getValue
    shconfig = YAML::load_file("testconfig.yml")

    SMSConfig.hasKey(shconfig, "users.name")
    #Config.getValue('sd')
  end
end