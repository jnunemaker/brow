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

  def test_push
    event = {foo: "bar"}
    client = build_client
    client.push(event)
    item = @queue.pop
    assert_equal event, item
  end

  def test_push_string_keys
    event = {foo: "bar"}
    client = build_client
    client.push({"foo" => "bar"})
    item = @queue.pop
    assert_equal event, item
  end

  def test_push_with_dates_and_times
    event = {
      time: Time.utc(2013, 1, 1, 1, 1, 2, 23),
      date_time: DateTime.new(2013, 1, 1, 1, 1, 10),
      date: Date.new(2013, 1, 1),
    }
    client = build_client

    client.push(event)
    expected = {
      time: "2013-01-01T01:01:02.000023Z",
      date_time: "2013-01-01T01:01:10.000000+00:00",
      date: "2013-01-01",
    }
    item = @queue.pop
    assert_equal expected, item
  end

  def test_push_without_hash
    client = build_client
    assert_raises ArgumentError do
      client.push("nope")
    end
  end

  def test_push_when_full
    event = {foo: "bar"}
    client = build_client(max_queue_size: 1)
    assert client.push(event)
    refute client.push(event)
  end

  def test_push_and_shutdown_start_and_stop_worker
    client = build_client

    assert_nil client.instance_variable_get("@worker_thread")
    client.push(n: 1)
    assert_instance_of Thread, client.instance_variable_get("@worker_thread")

    client.shutdown
    sleep 0.2
    refute_predicate client.instance_variable_get("@worker_thread"), :alive?
  end

  def test_flush_waits_for_the_queue_to_finish_on_a_flush
    client = build_client(worker: DummyWorker.new(@queue))
    client.push foo: "bar"
    client.push foo: "bar"
    client.flush
    assert_equal 0, client.queued_messages
  end

  def test_flush_completes_when_the_process_forks
    client = build_client(worker: DummyWorker.new(@queue))
    client.push foo: "bar"
    Process.fork do
      client.push foo: "bar"
      client.flush
      assert_equal 0, client.queued_messages
    end
    Process.wait
  end

  def test_test_mode
    event = {foo: "bar"}
    client = build_client(test: true)
    5.times { assert client.push(event) }
    assert_equal 5, client.test_queue.size
    assert_equal 0, @queue.size
  end

  def test_flushes_at_exit
    begin
      server = FakeServer.new
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        shutdown_automatically: true,
        retries: 2,
      })

      pid = fork {
        client.push(n: 1)
      }
      Process.waitpid pid, 0

      assert_equal 1, server.requests.size
      request = server.requests.first
      assert_equal "/events", request.path
      assert_equal pid, Integer(request.env.fetch("HTTP_CLIENT_PID"))
    ensure
      server.shutdown
    end
  end

  def test_flushes_queue_when_forked
    begin
      server = FakeServer.new
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        shutdown_automatically: true,
        retries: 2,
      })
      client.push(n: 1)

      pid = fork {
        client.push(n: 2)
      }
      Process.waitpid pid, 0

      assert_equal 2, server.requests.size

      request = server.requests.first
      assert_equal "/events", request.path
      assert_equal Process.pid, Integer(request.env.fetch("HTTP_CLIENT_PID"))

      request = server.requests.last
      assert_equal "/events", request.path
      assert_equal pid, Integer(request.env.fetch("HTTP_CLIENT_PID"))
    ensure
      server.shutdown
    end
  end

  def test_clears_mutexes_when_forked
    begin
      server = FakeServer.new
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        retries: 2,
        shutdown_automatically: true,
      })

      client.instance_variable_get("@worker_mutex").lock

      pid = fork {
        client.push(n: 1)
      }
      Process.waitpid pid, 0

      assert_equal 1, server.requests.size
      request = server.requests.first
      assert_equal "/events", request.path
      assert_equal pid, Integer(request.env.fetch("HTTP_CLIENT_PID"))
    ensure
      server.shutdown
    end
  end

  private

  def build_client(options = {})
    Brow::Client.new({
      worker: @worker,
      queue: @queue,
      shutdown_automatically: false,
    }.merge(options))
  end
end
