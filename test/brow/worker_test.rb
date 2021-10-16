require "test_helper"

class BrowWorkerTest < Minitest::Test
  def test_initialize
    queue = Queue.new
    worker = Brow::Worker.new(queue)
    assert_instance_of Brow::Transport, worker.instance_variable_get("@transport")
    assert_instance_of Brow::MessageBatch, worker.instance_variable_get("@batch")
    assert_equal 100, worker.instance_variable_get("@batch").instance_variable_get("@max_size")
    assert_equal Brow.logger, worker.instance_variable_get("@logger")
  end

  def test_initialize_with_options
    queue = Queue.new
    on_error = ->(*) { }
    transport = NoopTransport.new
    logger = Logger.new(STDOUT)
    batch = Brow::MessageBatch.new
    worker = Brow::Worker.new(queue, {
      on_error: on_error,
      transport: transport,
      logger: logger,
      batch: batch,
    })
    assert_equal on_error, worker.instance_variable_get("@on_error")
    assert_equal transport, worker.instance_variable_get("@transport")
    assert_equal logger, worker.instance_variable_get("@logger")
    assert_equal batch, worker.instance_variable_get("@batch")
  end

  def test_initialize_with_transport_options
    queue = Queue.new
    worker = Brow::Worker.new(queue, {
      url: "https://foo.com/bar",
      retries: 5,
      read_timeout: 1,
      open_timeout: 2,
    })
    transport = worker.instance_variable_get("@transport")
    assert_equal "foo.com", transport.instance_variable_get("@host")
    assert_equal "/bar", transport.instance_variable_get("@path")
    assert_equal 5, transport.instance_variable_get("@retries")

    http = transport.instance_variable_get("@http")
    assert_equal 1, http.read_timeout
    assert_equal 2, http.open_timeout
  end

  def test_initialize_with_batch_size
    queue = Queue.new
    worker = Brow::Worker.new(queue, {
      batch_size: 3,
      transport: NoopTransport.new,
    })
    assert_equal 3, worker.instance_variable_get("@batch").instance_variable_get("@max_size")
  end

  def test_run_does_not_error_if_the_request_fails
    queue = Queue.new
    queue << {foo: "bar"}
    transport = NoopTransport.new
    transport.stub :send_batch, Brow::Response.new(-1, "Unknown Error") do
      worker = Brow::Worker.new(queue, transport: transport)
      worker.run
      assert_predicate queue, :empty?
    end
  end

  def test_run_with_invalid_request
    queue = Queue.new
    queue << {foo: "bar"}
    transport = NoopTransport.new
    transport.stub :send_batch, Brow::Response.new(400, "Some Error") do
      status = error = nil
      on_error = proc do |yielded_status, yielded_error|
        sleep 0.2 # Make this take longer than thread spin-up (below)
        status, error = yielded_status, yielded_error
      end
      worker = Brow::Worker.new(queue, transport: transport, on_error: on_error)

      # This is to ensure that Client#flush doesn't finish before calling
      # the error handler.
      Thread.new { worker.run }
      sleep 0.1 # First give thread time to spin-up.
      sleep 0.01 while worker.requesting?

      assert_predicate queue, :empty?
      assert_equal 400, status
      assert_equal "Some Error", error
    end
  end

  def test_run_with_valid_request
    calls = []
    on_error = proc do |status, error|
      calls << [status, error]
    end

    queue = Queue.new
    worker = Brow::Worker.new(queue, {
      on_error: on_error,
      transport: NoopTransport.new,
    })
    worker.run
    assert_predicate queue, :empty?
    assert_predicate calls, :empty?
  end

  def test_run_with_bad_json
    bad = Object.new
    def bad.to_json(*_args)
      raise "can't serialize to json"
    end

    calls = []
    on_error = proc do |status, error|
      calls << [status, error]
    end

    transport = NoopTransport.new
    queue = Queue.new
    queue << {foo: "bar"}
    queue << {bad: bad}
    worker = Brow::Worker.new(queue, on_error: on_error, transport: transport)
    worker.run

    assert_predicate queue, :empty?
    assert_equal 1, calls.size, "Expected calls.size to be 1 but was #{calls.size} (calls: #{calls.inspect})"
    assert_instance_of Brow::MessageBatch::JSONGenerationError, calls[0][1]
  end

  def test_requesting_without_current_batch
    queue = Queue.new
    worker = Brow::Worker.new(queue, transport: NoopTransport.new)
    refute_predicate worker, :requesting?
  end

  def test_requesting_with_current_batch
    queue = Queue.new
    queue << {foo: "bar"}
    transport = NoopTransport.new
    response = ->(*) {
      sleep 0.2
      Brow::Response.new(200, 'Success')
    }
    transport.stub :send_batch, response do
      worker = Brow::Worker.new(queue, transport: transport)

      worker_thread = Thread.new { worker.run }
      eventually { worker.requesting? }

      worker_thread.join
      refute worker.requesting?
    end
  end

  private

  def eventually(options = {}, &block)
    timeout = options[:timeout] || 2
    interval = options[:interval] || 0.1
    time_limit = Time.now + timeout

    loop do
      result = yield
      return if result

      raise "Timeout waiting for block to return true" if Time.now >= time_limit
      sleep interval
    end
  end
end
