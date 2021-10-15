# frozen_string_literal: true

require "test_helper"

class BrowBackoffPolicyTest < Minitest::Test
  def test_initialize_with_no_options
    policy = Brow::BackoffPolicy.new
    assert_equal policy.instance_variable_get("@min_timeout_ms"), 100
    assert_equal policy.instance_variable_get("@max_timeout_ms"), 10_000
    assert_equal policy.instance_variable_get("@multiplier"), 1.5
    assert_equal policy.instance_variable_get("@randomization_factor"), 0.5
  end

  def test_initialize_with_options
    policy = Brow::BackoffPolicy.new({
      min_timeout_ms: 1234,
      max_timeout_ms: 5678,
      multiplier: 24,
      randomization_factor: 0.4,
    })
    assert_equal policy.instance_variable_get("@min_timeout_ms"), 1234
    assert_equal policy.instance_variable_get("@max_timeout_ms"), 5678
    assert_equal policy.instance_variable_get("@multiplier"), 24
    assert_equal policy.instance_variable_get("@randomization_factor"), 0.4
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
end
