require "test_helper"

class BrowClientTest < Minitest::Test
  def setup
    @queue = Queue.new
  end

  def test_initialize
    client = build_client

    assert_equal Brow.logger, client.logger
    assert_instance_of Brow::Worker, client.worker
  end

  def test_initialize_with_options
    queue = Queue.new
    logger = Logger.new(STDOUT)
    client = build_client({
      max_queue_size: 10,
      logger: logger,
      queue: queue,
    })

    assert_equal 10, client.worker.max_queue_size
    assert_equal queue, client.worker.queue
    assert_equal logger, client.logger
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

  # def test_push
  #   client = build_client

  #   assert_nil client.instance_variable_get("@worker_thread")
  #   client.push(n: 1)
  #   assert_instance_of Thread, client.instance_variable_get("@worker_thread")

  #   client.shutdown
  #   sleep 0.2
  #   refute_predicate client.instance_variable_get("@worker_thread"), :alive?
  # end

  def test_shutdown_at_exit
    begin
      server = FakeServer.new
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        shutdown_automatically: true,
        retries: 2,
      })

      pid = fork { client.push(n: 1) }
      Process.waitpid pid, 0

      assert_equal 1, server.requests.size
      request = server.requests.first
      assert_equal "/events", request.path
      assert_equal pid, Integer(request.env.fetch("HTTP_CLIENT_PID"))
    ensure
      server.shutdown
    end
  end

  def test_processes_queue_when_forked
    begin
      server = FakeServer.new
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        shutdown_automatically: true,
        retries: 2,
      })
      client.push(n: 1)

      pid = fork { client.push(n: 2) }
      Process.waitpid pid, 0

      # gotta shutdown the parent process worker
      client.worker.stop

      messages = server.requests.map(&:body).map(&:string).map { |text|
        JSON.parse(text).fetch("messages")
      }.flatten

      assert_equal [1, 2], messages.map { |message| message["n"] }.sort
      assert_equal ["/events"], server.requests.map(&:path).uniq
      pids = server.requests.map { |request|
        request.env.fetch("HTTP_CLIENT_PID")
      }
      assert_equal 2, pids.uniq.size
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

      client.worker.mutex.lock

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
      url: "http://example.com",
      queue: @queue,
      shutdown_automatically: false,
    }.merge(options))
  end
end
