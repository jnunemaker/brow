require "test_helper"

class BrowWorkerTest < Minitest::Test
  def test_initialize
    worker = Brow::Worker.new(valid_options)
    transport = worker.transport
    assert_instance_of Brow::Transport, transport
    assert_equal "https://example.com/", transport.url
    assert_equal 100, worker.batch_size
  end

  def test_initialize_with_invalid_max_queue_size
    assert_raises ArgumentError do
      worker = Brow::Worker.new(valid_options(max_queue_size: 0))
    end

    assert_raises ArgumentError do
      worker = Brow::Worker.new(valid_options(max_queue_size: -1))
    end
  end

  def test_initialize_with_invalid_batch_size
    assert_raises ArgumentError do
      worker = Brow::Worker.new(valid_options(batch_size: 0))
    end

    assert_raises ArgumentError do
      worker = Brow::Worker.new(valid_options(batch_size: -1))
    end
  end

  def test_initialize_with_invalid_shutdown_timeout
    assert_raises ArgumentError do
      worker = Brow::Worker.new(valid_options(shutdown_timeout: 0))
    end

    assert_raises ArgumentError do
      worker = Brow::Worker.new(valid_options(shutdown_timeout: -1))
    end
  end

  def test_initialize_with_options
    queue = Queue.new
    on_error = ->(*) { }
    transport = NoopTransport.new
    worker = Brow::Worker.new(valid_options({
      queue: queue,
      on_error: on_error,
      transport: transport,
      batch_size: 10,
      shutdown_automatically: false,
    }))
    assert_equal on_error, worker.on_error
    assert_equal transport, worker.transport
    assert_equal 10, worker.batch_size
  end

  def test_initialize_from_env
    env = {
      "BROW_BATCH_SIZE" => "1",
      "BROW_MAX_QUEUE_SIZE" => "2",
      "BROW_SHUTDOWN_TIMEOUT" => "100",
    }
    with_modified_env env do
      worker = Brow::Worker.new(valid_options.slice(:url))
      assert_equal 1, worker.batch_size
      assert_equal 2, worker.max_queue_size
      assert_equal 100.0, worker.shutdown_timeout
    end
  end

  def test_initialize_with_transport_options
    queue = Queue.new
    worker = Brow::Worker.new(valid_options({
      queue: queue,
      url: "https://foo.com/bar",
      retries: 5,
      read_timeout: 1,
      open_timeout: 2,
    }))
    transport = worker.transport
    assert_equal "https://foo.com/bar", transport.url
    assert_equal 5, transport.retries

    http = transport.http
    assert_equal 1, http.read_timeout
    assert_equal 2, http.open_timeout
  end

  def test_run_does_not_error_if_the_request_fails
    queue = Queue.new
    queue << {foo: "bar"}
    transport = NoopTransport.new
    transport.stub :send_batch, Brow::Response.new(-1, "Unknown Error") do
      worker = Brow::Worker.new(valid_options({
        queue: queue,
        transport: transport,
      }))
      worker.start
      worker.stop
      assert_predicate queue, :empty?
    end
  end

  def test_run_with_invalid_request
    queue = Queue.new
    queue << {"foo" => "bar"}
    transport = NoopTransport.new
    transport.stub :send_batch, Brow::Response.new(400, "Some Error") do
      status = error = nil
      on_error = proc do |yielded_response|
        sleep 0.2 # Make this take longer than thread spin-up (below)
        status, error = yielded_response.status, yielded_response.error
      end

      worker = Brow::Worker.new(valid_options({
        queue: queue,
        transport: transport,
        on_error: on_error,
      }))
      worker.start
      worker.stop

      assert_predicate queue, :empty?
      assert_equal 400, status
      assert_equal "Some Error", error
    end
  end

  def test_run_with_valid_request
    calls = []
    on_error = proc { |yielded_response| calls << yielded_response }

    queue = Queue.new
    queue << {"n" => 1}
    worker = Brow::Worker.new(valid_options({
      queue: queue,
      on_error: on_error,
      transport: NoopTransport.new,
    }))
    worker.start
    worker.stop
    assert_predicate queue, :empty?
    assert_predicate calls, :empty?
  end

  def test_run_with_bad_json
    bad = Object.new
    def bad.to_json(*_args)
      raise "can't serialize to json"
    end

    calls = []
    on_error = proc { |yielded_response| calls << yielded_response }
    transport = NoopTransport.new
    queue = Queue.new
    queue << {foo: "bar"}
    queue << {bad: bad}
    worker = Brow::Worker.new(valid_options({
      queue: queue,
      on_error: on_error,
      transport: transport,
    }))
    worker.start
    worker.stop

    assert_predicate queue, :empty?
    assert_equal 1, calls.size, "Expected calls.size to be 1 but was #{calls.size} (calls: #{calls.inspect})"
    assert_instance_of Brow::MessageBatch::JSONGenerationError, calls[0].error
  end

  private

  def valid_options(options = {})
    {
      url: "https://example.com/",
      shutdown_automatically: false,
      start_automatically: false,
    }.merge(options)
  end
end
