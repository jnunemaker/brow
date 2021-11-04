# frozen_string_literal: true

require "test_helper"

class BrowBackoffPolicyTest < Minitest::Test
  def test_initialize_with_no_options
    policy = Brow::BackoffPolicy.new
    assert_equal policy.min_timeout_ms, 100
    assert_equal policy.max_timeout_ms, 10_000
    assert_equal policy.multiplier, 1.5
    assert_equal policy.randomization_factor, 0.5
  end

  def test_initialize_with_options
    policy = Brow::BackoffPolicy.new({
      min_timeout_ms: 1234,
      max_timeout_ms: 5678,
      multiplier: 24,
      randomization_factor: 0.4,
    })
    assert_equal policy.min_timeout_ms, 1234
    assert_equal policy.max_timeout_ms, 5678
    assert_equal policy.multiplier, 24
    assert_equal policy.randomization_factor, 0.4
  end

  def test_initialize_with_min_higher_than_max
    error = assert_raises ArgumentError do
      Brow::BackoffPolicy.new({
        min_timeout_ms: 2,
        max_timeout_ms: 1,
      })
    end
    assert_equal ":min_timeout_ms (2) must be <= :max_timeout_ms (1)",
      error.message
  end

  def test_initialize_with_invalid_min_timeout_ms
    error = assert_raises ArgumentError do
      Brow::BackoffPolicy.new({
        min_timeout_ms: -1,
      })
    end
    assert_equal ":min_timeout_ms must be >= 0 but was -1", error.message
  end

  def test_initialize_with_invalid_max_timeout_ms
    error = assert_raises ArgumentError do
      Brow::BackoffPolicy.new({
        max_timeout_ms: -1,
      })
    end
    assert_equal ":max_timeout_ms must be >= 0 but was -1", error.message
  end

  def test_initialize_from_env
    env = {
      "BROW_BACKOFF_MIN_TIMEOUT_MS" => "1000",
      "BROW_BACKOFF_MAX_TIMEOUT_MS" => "2000",
      "BROW_BACKOFF_MULTIPLIER" => "1.9",
      "BROW_BACKOFF_RANDOMIZATION_FACTOR" => "0.1",
    }
    with_modified_env env do
      policy = Brow::BackoffPolicy.new
      assert_equal 1_000, policy.min_timeout_ms
      assert_equal 2_000, policy.max_timeout_ms
      assert_equal 1.9, policy.multiplier
      assert_equal 0.1, policy.randomization_factor
    end
  end

  def test_next_interval
    policy = Brow::BackoffPolicy.new({
      min_timeout_ms: 1_000,
      max_timeout_ms: 10_000,
      multiplier: 2,
      randomization_factor: 0.5,
    })

    assert_in_delta 1000, policy.next_interval, 500
    assert_in_delta 2000, policy.next_interval, 1000
    assert_in_delta 4000, policy.next_interval, 2000
    assert_in_delta 8000, policy.next_interval, 4000
  end

  def test_next_interval_caps_maximum_duration_at_max_timeout_secs
    policy = Brow::BackoffPolicy.new({
      min_timeout_ms: 1_000,
      max_timeout_ms: 10_000,
      multiplier: 2,
      randomization_factor: 0.5,
    })
    10.times { policy.next_interval }
    assert_equal 10_000, policy.next_interval
  end

  def test_reset
    policy = Brow::BackoffPolicy.new({
      min_timeout_ms: 1_000,
      max_timeout_ms: 10_000,
      multiplier: 2,
      randomization_factor: 0.5,
    })
    10.times { policy.next_interval }

    assert_equal 10, policy.attempts
    policy.reset
    assert_equal 0, policy.attempts
  end
end
