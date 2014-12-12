require 'time'
require 'hashie/mash'

module Resque::Plugins::Retry
  module RobotRules
    class Rule < Hashie::Mash
      def initialize(*args)
        super(*args)

        # pre-process rules as we are going to use them.
        # RobotRules.rules should be in a before_fork_hook, so we an do this there and save time later.

        if action.is_a?(Array) && RobotRules::ACTIONS.map(&:to_s).include?(action.first)
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
        if expiry
          begin
            self.expiry = Time.parse(self.expiry)
          rescue ArgumentError
            self.expiry = nil
          end
        end
      end

      def match?(job, exception, args)
        return false if class_regex && ! (job.class.name =~ class_regex)
        return false if exception_class_regex && ! (exception.class.name =~ exception_class_regex)
        return false if exception_message_regex && ! (exception.message =~ exception_message_regex)
        return false if expiry && Time.now > expiry
        return false if args_json_regex && ! (args.to_json =~ args_json_regex)
        return false if job.retry_limit_reached? && action.first.to_s.include?('retry')
        return false if percent_chance && rand > percent_chance
        return true
      end

      def action
        @action || super.tap do |action|
        end
      end
    end

    ACTIONS = [:retry, :clear, :retry_increment_retry_attempt]

    def rules
      Damnl.get('resque_retry_robot_rules', default: '[]') do |rs|
        rs.map { |rule_hash| Rule.new(hash) }
      end
    end

    # returns an ACTION, or nil
    # TODO: built in max_retyr here
    def self.action_and_arguments(job, exception, args)
      rules.each do
        return rule.action  if rule.match?(job, exception, args)
      end
      nil
    end

  end
end
