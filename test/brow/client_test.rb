require "test_helper"

class BrowClientTest < Minitest::Test
  def setup
    @queue = Queue.new
    stub_request(:post, "http://example.com/").
      to_return(status: 200, body: "", headers: {})
    super
  end

  def test_initialize
    client = build_client
    assert_instance_of Brow::Worker, client.worker
  end

  def test_initialize_with_options
    queue = Queue.new
    client = build_client({
      max_queue_size: 10,
      queue: queue,
    })

    assert_equal 10, client.worker.max_queue_size
    assert_equal queue, client.worker.queue
  end

  def test_push_symbol_keys
    client = build_client
    client.push(foo: "bar")
    item = @queue.pop
    expected = {foo: "bar"}
    assert_equal expected, item
  ensure
    client.worker.stop
  end

  def test_push_string_keys
    client = build_client
    client.push("foo" => "bar")
    item = @queue.pop
    expected = {"foo" => "bar"}
    assert_equal expected, item
  ensure
    client.worker.stop
  end

  def test_push_with_dates_and_times
    event = {
      time: Time.utc(2013, 1, 1, 1, 1, 2, 23),
      "date_time" => DateTime.new(2013, 1, 1, 1, 1, 10),
      date: Date.new(2013, 1, 1),
    }
    client = build_client

    client.push(event)
    expected = {
      time: "2013-01-01T01:01:02.000023Z",
      "date_time" => "2013-01-01T01:01:10.000000+00:00",
      date: "2013-01-01",
    }
    item = @queue.pop
    assert_equal expected, item
  ensure
    client.worker.stop
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
    # ensure the worker thread doesn't start up to work off the queue
    client.worker.mutex.lock
    assert client.push(event)
    refute client.push(event)
  end

  def test_push_starts
    client = build_client(start_automatically: true)

    assert_nil client.worker.thread
    client.push(n: 1)
    assert_instance_of Thread, client.worker.thread

    client.worker.stop
    sleep 0.2
    refute_predicate client.worker.thread, :alive?
  end

  def test_shutdown_at_exit
    FakeServer.new do |server|
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        shutdown_automatically: true,
        start_automatically: true,
        retries: 2,
      })

      pid = fork { client.push(n: 1) }
      Process.waitpid pid, 0

      assert_equal 1, server.requests.size
      request = server.requests.first
      assert_equal "/events", request.path
      assert_equal pid, Integer(request.headers.fetch("client-pid"))

      assert_equal "Brow v#{Brow::VERSION}", request.headers["user-agent"]
      assert_equal "ruby", request.headers["client-language"]
      assert_equal "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
        request.headers["client-language-version"]

      assert_equal RUBY_PLATFORM, request.headers["client-platform"]
      assert_equal RUBY_ENGINE, request.headers["client-engine"]
      refute_nil request.headers["client-hostname"]
    end
  end

  def test_processes_queue_when_forked
    FakeServer.new do |server|
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        shutdown_automatically: true,
        start_automatically: true,
        retries: 2,
      })
      client.push(n: 1)

      pid = fork { client.push(n: 2) }
      Process.waitpid pid, 0

      # gotta shutdown the parent process worker
      client.worker.stop

      messages = server.requests.map(&:body).map { |text|
        JSON.parse(text).fetch("messages")
      }.flatten

      assert_equal [1, 2], messages.map { |message| message["n"] }.sort
      assert_equal ["/events"], server.requests.map(&:path).uniq
      pids = server.requests.map { |request|
        request.headers.fetch("client-pid")
      }
      assert_equal 2, pids.uniq.size
    end
  end

  def test_clears_mutexes_when_forked
    FakeServer.new do |server|
      client = Brow::Client.new({
        url: "http://localhost:#{server.port}/events",
        retries: 2,
        shutdown_automatically: true,
        start_automatically: true,
      })

      client.worker.mutex.lock

      pid = fork {
        client.push(n: 1)
      }
      Process.waitpid pid, 0

      assert_equal 1, server.requests.size
      request = server.requests.first
      assert_equal "/events", request.path
      assert_equal pid, Integer(request.headers.fetch("client-pid"))
    end
  end

  private

  def build_client(options = {})
    Brow::Client.new({
      url: "http://example.com",
      queue: @queue,
      shutdown_automatically: false,
      start_automatically: false,
    }.merge(options))
  end
end
