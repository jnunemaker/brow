# frozen_string_literal: true

module Brow
  class BackoffPolicy
    # Private: The default minimum timeout between intervals in milliseconds.
    MIN_TIMEOUT_MS = 100

    # Private: The default maximum timeout between intervals in milliseconds.
    MAX_TIMEOUT_MS = 10_000

    # Private: The value to multiply the current interval with for each
    # retry attempt.
    MULTIPLIER = 1.5

    # Private: The randomization factor to use to create a range around the
    # retry interval.
    RANDOMIZATION_FACTOR = 0.5

    # Private
    attr_reader :min_timeout_ms, :max_timeout_ms, :multiplier, :randomization_factor

    # Private
    attr_reader :attempts

    # Public: Create new instance of backoff policy.
    #
    # options - The Hash of options.
    #   :min_timeout_ms - The minimum backoff timeout.
    #   :max_timeout_ms - The maximum backoff timeout.
    #   :multiplier - The value to multiply the current interval with for each
    #                 retry attempt.
    #   :randomization_factor - The randomization factor to use to create a range
    #                           around the retry interval.
    def initialize(options = {})
      @min_timeout_ms = options[:min_timeout_ms] || MIN_TIMEOUT_MS
      @max_timeout_ms = options[:max_timeout_ms] || MAX_TIMEOUT_MS
      @multiplier = options[:multiplier] || MULTIPLIER
      @randomization_factor = options[:randomization_factor] || RANDOMIZATION_FACTOR

      @attempts = 0
    end

    # Public: Returns the next backoff interval in milliseconds.
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
