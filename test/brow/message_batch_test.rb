require "test_helper"

class BrowMessageBatchTest < Minitest::Test
  def test_append_message
    message = {"foo" => "bar"}
    batch = Brow::MessageBatch.new(max_size: 100)
    batch << message
    assert_equal 1, batch.length
  end

  def test_append_message_rejects_too_large_messages
    message = {"a" => "b" * Brow::MessageBatch::MESSAGE_MAX_BYTES}
    batch = Brow::MessageBatch.new(max_size: 100)
    batch << message
    assert_equal 0, batch.length
  end

  def test_full_returns_true_when_max_size_exceeded
    batch = Brow::MessageBatch.new(max_size: 100)
    99.times { batch << {"a" => "b"}}
    refute_predicate batch, :full?
    batch << {"a" => "b"}
    assert_predicate batch, :full?
  end

  def test_full_returns_true_when_max_bytes_exceeded
    batch = Brow::MessageBatch.new(max_size: 100)
    message = {a: 'b' * (Brow::MessageBatch::MESSAGE_MAX_BYTES - 10)}
    message_size = message.to_json.bytesize

    # Each message is under the individual limit
    assert message_size < Brow::MessageBatch::MESSAGE_MAX_BYTES

    # Size of the batch is over the limit
    assert (50 * message_size) > Brow::MessageBatch::MAX_BYTES

    refute_predicate batch, :full?
    50.times { batch << message }
    assert_predicate batch, :full?
  end
end
