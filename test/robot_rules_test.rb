require 'test_helper'

class RobotRulesTest < MiniTest::Unit::TestCase
  class MyObject < Struct.new(:name, :retry_limit_reached?, :retry_attempt)
  end

  def setup
    Resque.redis.flushall
  end

  def test_bad_rules_doesnt_crash
    Damnl.send(:cached_versions)['resque_retry_robot_rules'] = -1 # Hack to force reloading since we cleared Redis
    Damnl.set('resque_retry_robot_rules', [
      {'chance' => 'ok', 'bogus' => 'no'},
      {'class_regex' => 'bad regex]]))/\\1'},
      {'exception_message_regex' => '[bad regex'},
      {'args_json_regex' => 1},
      {'exception_class_regex' => 123},
      {'expiry' => /3$:@L#@$:/, 'action' => -1.5, 'action_args' => true},
    ].to_yaml)

    assert_equal [nil,[true]], Resque::Plugins::Retry::RobotRules.action_and_arguments(MyObject.new(true), StandardError.new('foo'), [2,'okay'])
  end

  def test_match
    Damnl.send(:cached_versions)['resque_retry_robot_rules'] = -1 # Hack to force reloading since we cleared Redis
    Damnl.set('resque_retry_robot_rules', [
      {'args_json_regex' => ',"okay",', 'expiry' => '2086-10-01T21:14:21', 'action' => 'bogus_action_turned_into_nil'},
      {'exception_message_regex' => 'explicitretrylimit', 'action' => 'retry', 'retry_limit' => 500},
      {'class_regex' => '[oO]bject', 'exception_class_regex' => '^[sS]tandard', 'action' => 'retry'},
      {'exception_message_regex' => 'h.llo', 'expiry' => 'bogus_so_ignored', 'action' => 'clear'},
      {'chance' => 1, 'args_json_regex' => ',"ok",', 'expiry' => '2086-10-01T21:14:21', 'action' => 'retry_increment_retry_attempt', 'action_args' => [2]},
      {'chance' => 0, 'action' => 'retry_increment_retry_attempt', 'action_args' => [99]}, # this will never trigger
      {'expiry' => '2014-12-09-T14:24:23', 'action' => 'retry_increment_retry_attempt', 'action_args' => [99]} # this will never trigger
    ].to_yaml)

    job1 = MyObject.new('MyObject', false, 10)
    job2 = MyObject.new('MyObject', true, 10)
    job3 = MyObject.new('Struct', false, 10)
    exception1 = StandardError.new('foo')
    exception2 = Exception.new('well hello')

    assert_equal [:retry,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job1, exception1, [])
    assert_equal [nil,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job1, exception1, [1,'okay',2])
    assert_equal [:clear,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job1, exception2, [])
    assert_equal [nil,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job2, exception1, [])
    assert_equal [:clear,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job2, exception2, [])
    assert_equal [nil,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job3, exception1, [])
    assert_equal [:retry_increment_retry_attempt, [2]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job3, exception1, [1,'ok',2])
    assert_equal [:clear, []], Resque::Plugins::Retry::RobotRules.action_and_arguments(job3, exception2, [])

    job4 = MyObject.new('MyObject', true, 499)
    job5 = MyObject.new('MyObject', true, 500)
    exception3 = StandardError.new('explicitretrylimit')
    assert_equal [:retry,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job4, exception3, [])
    assert_equal [nil,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(job5, exception3, [])

  end

  def teardown
    Resque.redis.flushall
  end
end
