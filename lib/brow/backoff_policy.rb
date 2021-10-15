# frozen_string_literal: true

module Brow
  class BackoffPolicy
    MIN_TIMEOUT_MS = 100
    MAX_TIMEOUT_MS = 10000
    MULTIPLIER = 1.5
    RANDOMIZATION_FACTOR = 0.5

    # @param [Hash] options
    # @option options [Numeric] :min_timeout_ms The minimum backoff timeout
    # @option options [Numeric] :max_timeout_ms The maximum backoff timeout
    # @option options [Numeric] :multiplier The value to multiply the current
    #   interval with for each retry attempt
    # @option options [Numeric] :randomization_factor The randomization factor
    #   to use to create a range around the retry interval
    def initialize(options = {})
      @min_timeout_ms = options[:min_timeout_ms] || MIN_TIMEOUT_MS
      @max_timeout_ms = options[:max_timeout_ms] || MAX_TIMEOUT_MS
      @multiplier = options[:multiplier] || MULTIPLIER
      @randomization_factor = options[:randomization_factor] || RANDOMIZATION_FACTOR

      @attempts = 0
    end

    # @return [Numeric] the next backoff interval, in milliseconds.
    def next_interval
      interval = @min_timeout_ms * (@multiplier**@attempts)
      interval = add_jitter(interval, @randomization_factor)

      @attempts += 1

      [interval, @max_timeout_ms].min
    end

    private

    def add_jitter(base, randomization_factor)
      random_number = rand
      max_deviation = base * randomization_factor
      deviation = random_number * max_deviation

      if random_number < 0.5
        base - deviation
      else
        base + deviation
      end
    end
  end
end
