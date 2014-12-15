require 'test_helper'

class RobotRulesTest < MiniTest::Unit::TestCase
  class MyObject < Struct.new(:retry_limit_reached?)
  end

  def setup
    Resque.redis.flushall
  end

  def test_bad_rules_doesnt_crash
    Damnl.send(:cached_versions)['resque_retry_robot_rules'] = -1 # Hack to force reloading since we cleared Redis
    Damnl.set('resque_retry_robot_rules', [
      {'args_json_regex' => 1, 'expiry' => /3$:@L#@$:/, 'action' => -1.5, 'action_args' => true, 'exception_message_regex' => '[bad regex',
       'exception_class_regex' => 123, 'class_regex' => 'bad regex]]))/\\1', 'chance' => 'ok', 'bogus' => 'no'}
    ].to_yaml)

    assert_equal [nil,[]], Resque::Plugins::Retry::RobotRules.action_and_arguments(MyObject.new(true), StandardError.new('foo'), [1,'okay'])
  end

  def test_match
    Damnl.send(:cached_versions)['resque_retry_robot_rules'] = -1 # Hack to force reloading since we cleared Redis
    Damnl.set('resque_retry_robot_rules', [
      {'args_json_regex' => ',"okay",', 'expiry' => '2086-10-01T21:14:21', 'action' => 'bogus_action_turned_into_nil'},
      {'class_regex' => '[oO]bject', 'exception_class_regex' => '^[sS]tandard', 'action' => 'retry'},
      {'exception_message_regex' => 'h.llo', 'expiry' => 'bogus_so_ignored', 'action' => 'clear'},
      {'chance' => 1, 'args_json_regex' => ',"ok",', 'expiry' => '2086-10-01T21:14:21', 'action' => 'retry_increment_retry_attempt', 'action_args' => [2]},
      {'chance' => 0, 'action' => 'retry_increment_retry_attempt', 'action_args' => [99]}, # this will never trigger
      {'expiry' => '2014-12-09-T14:24:23', 'action' => 'retry_increment_retry_attempt', 'action_args' => [99]} # this will never trigger
    ].to_yaml)

    job1 = MyObject.new(false)
    job2 = MyObject.new(true)
    job3 = Struct.new(:retry_limit_reached?).new(false)
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
  end

  def teardown
    Resque.redis.flushall
  end
end
