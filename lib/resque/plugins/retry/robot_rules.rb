require 'time'
require 'hashie/mash'
require 'damnl'

module Resque::Plugins::Retry
  module RobotRules
    class Rule < Hashie::Mash
      def initialize(*args)
        super(*args)

        # pre-process rules as we are going to use them.
        # RobotRules.rules should be in a before_fork_hook, so we an do this there and save time later.

        if action_args.nil?
          self.action_args = []
        else
          self.action_args = Array(self.action_args)
        end

        if RobotRules::ACTIONS.map(&:to_s).include?(action)
          self.action = action.to_sym
        else
          self.action = nil
        end

        # Precompile regexes
        [:class_regex, :exception_class_regex, :exception_message_regex, :args_json_regex].each do |regex_name|
          if send(regex_name)
            send(:"#{regex_name}=", /#{send(regex_name)}/)
          end
        end

        # Parse time
        self.expiry = (Time.parse(self.expiry) rescue nil)  if expiry
      end

      def match?(job, exception, args)
        return false if class_regex && ! (job.class.name =~ class_regex)
        return false if exception_class_regex && ! (exception.class.name =~ exception_class_regex)
        return false if exception_message_regex && ! (exception.message =~ exception_message_regex)
        return false if expiry && Time.now > expiry
        return false if args_json_regex && ! (args.to_json =~ args_json_regex)
        return false if chance && rand > chance
        return true
      end
    end

    ACTIONS = [:retry, :clear, :retry_increment_retry_attempt]

    def self.rules
      Damnl.get('resque_retry_robot_rules', default: '[]') do |rs|
        rs.map { |rule_hash| Rule.new(rule_hash) }
      end
    end

    # returns [action, arguments_array_or_nil], or [nil, nil]
    def self.action_and_arguments(job, exception, args)
      rules.each do |rule|
        if rule.match?(job, exception, args)
          if (rule.action == :retry || rule.action == :retry_increment_retry_attempt) && job.retry_limit_reached?
            # Don't retry a job which has reached its retry limit.
            return [nil, []]
          else
            return [rule.action, rule.action_args]
          end
        end
      end
      [nil, []]
    end

  end
end
