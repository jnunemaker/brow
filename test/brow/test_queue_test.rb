require "test_helper"

class BrowTestQueueTest < Minitest::Test
  def test_initialize
    test_queue = Brow::TestQueue.new
    assert_predicate test_queue.messages, :empty?
  end

  def test_append
    message = {foo: "bar"}
    test_queue = Brow::TestQueue.new
    test_queue << message
    assert_equal [message], test_queue.messages
  end

  def test_count
    message = {foo: "bar"}
    test_queue = Brow::TestQueue.new
    assert_equal 0, test_queue.count

    test_queue << message
    assert_equal 1, test_queue.count

    test_queue << message
    assert_equal 2, test_queue.count
  end

  def test_reset
    message = {foo: "bar"}
    test_queue = Brow::TestQueue.new
    test_queue << message

    test_queue.reset
    assert_predicate test_queue.messages, :empty?
  end
end
