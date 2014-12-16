require File.dirname(__FILE__) + '/test_helper'

class RobotRulesRetryCriteriaTest < MiniTest::Unit::TestCase
  class RobotRulesMockFailureBackend < Resque::Failure::Base
    class << self
      attr_accessor :errors
    end

    def save
      self.class.errors << exception.to_s
    end

    self.errors = []
  end

  def setup
    Resque.redis.flushall
    @worker = Resque::Worker.new(:testing)
    @worker.register_worker

    @old_failure_backend = Resque::Failure.backend
    RobotRulesMockFailureBackend.errors = []
    Resque::Failure::MultipleWithRetrySuppression.classes = [ RobotRulesMockFailureBackend ]
    Resque::Failure.backend = Resque::Failure::MultipleWithRetrySuppression

    setup_rules
  end
  def teardown
    Resque::Failure.backend = @old_failure_backend
  end

  module MyTest
    @queue = :testing
    @retry_exceptions = [Class.new] # Fake error cla. will never retry ... unless the rules tell it to
    extend Resque::Plugins::Retry
    def self.perform(arg)
      raise StandardError.new(arg)
    end
  end

  def setup_rules
    Damnl.send(:cached_versions)['resque_retry_robot_rules'] = -1 # Hack to force reloading since we cleared Redis
    Damnl.set('resque_retry_robot_rules', [
      {'exception_message_regex' => 'waz', 'action' => 'clear'},
      {'exception_message_regex' => 'bar', 'action' => 'retry_increment_retry_attempt', 'action_args' => 2, 'retry_limit' => 3},
      {'exception_message_regex' => 'foo', 'action' => 'retry', 'retry_limit' => 2}
    ].to_yaml)
  end

  def test_robot_rules_retry_criteria_check_should_retry
    Resque.enqueue(MyTest, 'foo')
    perform_next_job(@worker)

    assert_equal 1, Resque.info[:pending], 'pending jobs'
    assert_equal 0, RobotRulesMockFailureBackend.errors.count, 'jobs fallen through to failure backend'
    assert_equal 1, Resque.info[:processed], 'processed job'

    perform_next_job(@worker)

    assert_equal 1, Resque.info[:pending], 'pending jobs'
    assert_equal 0, RobotRulesMockFailureBackend.errors.count, 'jobs fallen through to failure backend'
    assert_equal 2, Resque.info[:processed], 'processed job'

    perform_next_job(@worker)

    assert_equal 0, Resque.info[:pending], 'pending jobs'
    assert_equal 1, RobotRulesMockFailureBackend.errors.count, 'jobs fallen through to failure backend'
    assert_equal 3, Resque.info[:processed], 'processed job'
  end

  def test_robot_rules_retry_criteria_check_should_retry_up_to_limit
    Resque.enqueue(MyTest, 'foo')
    Resque.enqueue(MyTest, 'foo')
    7.times { perform_next_job(@worker) }

    assert_equal 0, Resque.info[:pending], 'pending jobs'
    assert_equal 2, RobotRulesMockFailureBackend.errors.count, 'jobs fallen through to failure backend'
    assert_equal 6, Resque.info[:processed], 'processed job'
  end

  def test_robot_rules_retry_criteria_retry_increment_attempt
    Resque.enqueue(MyTest, 'bar')
    2.times { perform_next_job(@worker) }

    assert_equal 0, Resque.info[:pending], 'pending jobs'
    assert_equal 1, RobotRulesMockFailureBackend.errors.count, 'jobs fallen through to failure backend'
    assert_equal 2, Resque.info[:processed], 'processed job'
  end

  def test_robot_rules_retry_criteria_clear
    Resque.enqueue(MyTest, 'waz')
    2.times { perform_next_job(@worker) }

    assert_equal 0, Resque.info[:pending], 'pending jobs'
    assert_equal 0, RobotRulesMockFailureBackend.errors.count, 'jobs fallen through to failure backend'
    assert_equal 1, Resque.info[:processed], 'processed job'
  end

  def test_robot_rules_raises_exception_all_is_not_lost
    tmp_old_value = ENV['RESQUE_RETRY_DEBUG']
    ENV['RESQUE_RETRY_DEBUG'] = nil
    Resque.enqueue(MyTest, 'foo')
    Resque::Plugins::Retry::RobotRules.expects(:action_and_arguments).raises(StandardError.new)
    perform_next_job(@worker)

    assert_equal 0, Resque.info[:pending], 'pending jobs'
    assert_equal 1, RobotRulesMockFailureBackend.errors.count, 'jobs fallen through to failure backend'
    assert_equal 1, Resque.info[:processed], 'processed job'
  ensure
    ENV['RESQUE_RETRY_DEBUG'] = tmp_old_value
  end
end



