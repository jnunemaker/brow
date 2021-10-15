require "test_helper"

class BrowClientTest < Minitest::Test
  def setup
    @queue = Queue.new
    @worker = NoopWorker.new
  end

  def test_initialize
    client = build_client

    assert_nil client.instance_variable_get("@test")
    assert_equal 10_000, client.instance_variable_get("@max_queue_size")
    assert_equal Brow.logger, client.instance_variable_get("@logger")
    assert_equal @queue, client.instance_variable_get("@queue")
    assert_equal @worker, client.instance_variable_get("@worker")
  end

  def test_initialize_with_options
    queue = Queue.new
    worker = NoopWorker.new
    logger = Logger.new(STDOUT)
    client = build_client({
      test: true,
      max_queue_size: 10,
      worker: worker,
      logger: logger,
      queue: queue,
    })

    assert client.instance_variable_get("@test")
    assert_equal 10, client.instance_variable_get("@max_queue_size")
    assert_equal worker, client.instance_variable_get("@worker")
    assert_equal logger, client.instance_variable_get("@logger")
    assert_equal queue, client.instance_variable_get("@queue")
  end

  def test_record
    event = {foo: "bar"}
    client = build_client
    client.record(event)
    item = @queue.pop
    assert_equal event, item
  end

  def test_record_string_keys
    event = {foo: "bar"}
    client = build_client
    client.record({"foo" => "bar"})
    item = @queue.pop
    assert_equal event, item
  end

  def test_record_when_full
    event = {foo: "bar"}
    client = build_client(max_queue_size: 1)
    assert client.record(event)
    refute client.record(event)
  end

  def test_flush_waits_for_the_queue_to_finish_on_a_flush
    client = build_client(worker: DummyWorker.new(@queue))
    client.record foo: "bar"
    client.record foo: "bar"
    client.flush
    assert_equal 0, client.queued_messages
  end

  def test_flush_completes_when_the_process_forks
    client = build_client(worker: DummyWorker.new(@queue))
    client.record foo: "bar"
    Process.fork do
      client.record foo: "bar"
      client.flush
      assert_equal 0, client.queued_messages
    end
    Process.wait
  end

  def test_test_mode
    event = {foo: "bar"}
    client = build_client(test: true)
    5.times { assert client.record(event) }
    assert_equal 5, client.test_queue.size
    assert_equal 0, @queue.size
  end

  private

  def build_client(options = {})
    Brow::Client.new({worker: @worker, queue: @queue}.merge(options))
  end
end
