require "test_helper"

class BrowMessageBatchTest < Minitest::Test

  def test_uuid
    batch = Brow::MessageBatch.new
    refute_nil batch.uuid
  end

  def test_clear
    message = {"foo" => "bar"}
    batch = Brow::MessageBatch.new
    original_uuid = batch.uuid
    10.times { batch << message }
    refute_predicate batch, :empty?
    assert batch.json_size > 0

    batch.clear
    refute_equal original_uuid, batch.uuid
    assert_predicate batch, :empty?
    assert_equal 0, batch.json_size
  end

  def test_as_json
    batch = Brow::MessageBatch.new
    3.times { |n| batch << {"number" => n}}
    expected = {
      uuid: batch.uuid,
      messages: [
        {"number" => 0},
        {"number" => 1},
        {"number" => 2},
      ]
    }
    assert_equal expected, batch.as_json
  end

  def test_append_message
    message = {"foo" => "bar"}
    batch = Brow::MessageBatch.new(max_size: 100)
    batch << message
    assert_equal 1, batch.length
  end

  def test_append_message_rejects_too_large_messages
    message = {"a" => "b" * Brow::MessageBatch::MAX_BYTES_PER_MESSAGE}
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
    message = {a: 'b' * (Brow::MessageBatch::MAX_BYTES_PER_MESSAGE - 10)}
    message_size = message.to_json.bytesize

    # Each message is under the individual limit
    assert message_size < Brow::MessageBatch::MAX_BYTES_PER_MESSAGE

    # Size of the batch is over the limit
    assert (50 * message_size) > Brow::MessageBatch::MAX_BYTES

    refute_predicate batch, :full?
    50.times { batch << message }
    assert_predicate batch, :full?
  end
end
