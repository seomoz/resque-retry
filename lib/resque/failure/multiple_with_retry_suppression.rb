require 'resque/failure/multiple'

module Resque
  module Failure

    # A multiple failure backend, with retry suppression.
    #
    # For example: if you had a job that could retry 5 times, your failure 
    # backends are not notified unless the _final_ retry attempt also fails.
    #
    # Example:
    #
    #   require 'resque-retry'
    #   require 'resque/failure/redis'
    #
    #   Resque::Failure::MultipleWithRetrySuppression.classes = [Resque::Failure::Redis]
    #   Resque::Failure.backend = Resque::Failure::MultipleWithRetrySuppression
    #
    class MultipleWithRetrySuppression < Multiple
      include Resque::Helpers

      # Called when the job fails.
      #
      # If the job will retry, suppress the failure from the other backends.
      # Store the lastest failure information in redis, used by the web
      # interface.
      def save
        if exception.is_a?(Resque::DirtyExit) || ! (retryable? && retrying?)
          cleanup_retry_failure_log!
          super
        elsif retry_delay > 0
          data = {
            :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S"),
            :payload   => payload,
            :exception => exception.class.to_s,
            :error     => exception.to_s,
            :backtrace => Array(exception.backtrace),
            :worker    => worker.to_s,
            :queue     => queue
          }

          redis.setex(failure_key, 2*retry_delay, Resque.encode(data))
        end
      end

      # Expose this for the hook's use.
      def self.failure_key(retry_key)
        'failure_' + retry_key
      end

      protected
      def klass
        constantize(payload['class'])
      end

      def retry_delay
        klass.retry_delay
      end

      def retry_key
        klass.redis_retry_key(payload['args'])
      end

      def failure_key
        self.class.failure_key(retry_key)
      end

      def retryable?
        klass.respond_to?(:redis_retry_key)
      rescue NameError
        false
      end

      def retrying?
        !! redis.get(retry_key).tap do |val|
          # Any value less than -1 (-3 to be on safe side) means
          # It's received a "clear" from the RobotRules.
          # count it as retying for our purposes -- don't send down
          # to other failure backens -- but clean up
          #
          # If we have many identical jobs AND an inconsistent
          # rule (e.g. with random number) it's possible
          # that other jobs could be incrementing the negative value
          # and here we essentially move it back to 0. So some jobs
          # may be retried extra rimes. This is a very rare
          # scenario though.
          if val.to_i < -3
            redis.del retry_key
          end
        end
      end

      def cleanup_retry_failure_log!
        redis.del(failure_key) if retryable?
      end
    end
  end
end
