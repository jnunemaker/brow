require "test_helper"

class BrowTransportTest < Minitest::Test
  def setup
    @batch = Brow::MessageBatch.new.tap { |b| b << {n: 1}}
    super
  end

  def test_initialize
    transport = Brow::Transport.new(url: "https://foo.com/bar")
    assert_equal "https://foo.com/bar", transport.url
  end

  def test_initialize_without_url
    assert_raises ArgumentError do
      Brow::Transport.new
    end
  end

  def test_initialize_from_env
    env = {
      "BROW_URL" => "https://foo.com/bar",
      "BROW_RETRIES" => "1",
      "BROW_READ_TIMEOUT" => "10",
      "BROW_OPEN_TIMEOUT" => "100",
      "BROW_WRITE_TIMEOUT" => "1000",
    }
    with_modified_env env do
      transport = Brow::Transport.new
      assert_equal "https://foo.com/bar", transport.url
      assert_equal 1, transport.retries
      assert_equal 10, transport.http.read_timeout
      assert_equal 100, transport.http.open_timeout

      if RUBY_VERSION >= '2.6.0'
        assert_equal 1_000, transport.http.write_timeout
      end
    end
  end

  def test_initialize_with_timeouts
    options = {
      url: "https://foo.com/bar",
      read_timeout: 1,
      open_timeout: 2,
      write_timeout: 3,
    }

    transport = Brow::Transport.new(options)
    assert_equal 1, transport.http.read_timeout
    assert_equal 2, transport.http.open_timeout

    if RUBY_VERSION >= '2.6.0'
      assert_equal 3, transport.http.write_timeout
    end
  end

  def test_initialize_with_options
    headers = {
      "Some-Token" => "asdf",
      "Accept"=>"text/plain",
      "Content-Type"=>"text/plain",
    }
    logger = Logger.new("/dev/null")
    backoff_policy = Brow::BackoffPolicy.new
    transport = Brow::Transport.new({
      url: "https://example.com",
      headers: headers,
      retries: 5,
      logger: logger,
      backoff_policy: backoff_policy,
    })

    assert_equal headers, transport.headers
    assert_equal logger, transport.logger
    assert_equal backoff_policy, transport.backoff_policy
    http = transport.http
    assert_predicate http, :use_ssl?
  end

  def test_send_batch_with_no_path
    stub_request(:post, "https://foo.com/").to_return(status: 201)

    transport = Brow::Transport.new(url: "https://foo.com", retries: 1)
    response = transport.send_batch(@batch)
    assert_equal 201, response.status
    assert_nil response.error
    assert_equal 0, transport.backoff_policy.attempts

    assert_requested :post, "https://foo.com/"
  end

  def test_send_batch
    stub_request(:post, "https://foo.com/bar")
      .with({
        headers: {
          "Accept" => "application/json",
          "Content-Type" => "application/json",
          "User-Agent" => "Brow v#{Brow::VERSION}",
        },
        body: @batch.to_json,
      })
      .to_return(status: 201)

    transport = Brow::Transport.new(url: "https://foo.com/bar")
    response = transport.send_batch(@batch)
    assert_equal 201, response.status
    assert_nil response.error
    assert_equal 0, transport.backoff_policy.attempts

    assert_requested :post, "https://foo.com/bar"
  end

  def test_send_batch_permanent_error
    [500, 503].each do |error_status_code|
      attempts = 0
      responder = -> (request) {
        attempts += 1
        {status: error_status_code}
      }
      stub_request(:post, "https://foo.com/bar").to_return(responder)

      transport = Brow::Transport.new({
        url: "https://foo.com/bar",
        retries: 2,
      })
      response = transport.send_batch(@batch)
      assert_equal error_status_code, response.status
      assert_equal 2, attempts
      assert_nil response.error
      assert_equal 0, transport.backoff_policy.attempts
    end
  end

  def test_send_batch_timeout
    stub_request(:post, "https://foo.com/bar").to_timeout

    transport = Brow::Transport.new({
      url: "https://foo.com/bar",
      retries: 2,
    })
    response = transport.send_batch(@batch)
    assert_equal (-1), response.status
    assert_equal "execution expired", response.error
    assert_equal 0, transport.backoff_policy.attempts
  end

  def test_send_batch_temporary_error
    [500, 503].each do |error_status_code|
      attempts = 0
      responder = -> (request) {
        attempts += 1
        attempts == 1 ? {status: error_status_code} : {status: 201}
      }
      stub_request(:post, "https://foo.com/bar").to_return(responder)

      transport = Brow::Transport.new({
        url: "https://foo.com/bar",
        retries: 2,
      })
      response = transport.send_batch(@batch)
      assert_equal 201, response.status
      assert_equal 2, attempts
      assert_nil response.error
      assert_equal 0, transport.backoff_policy.attempts
    end
  end

  def test_send_batch_rate_limit_error
    attempts = 0
    responder = -> (request) {
      attempts += 1
      attempts == 1 ? {status: 429} : {status: 201}
    }
    stub_request(:post, "https://foo.com/bar").to_return(responder)

    transport = Brow::Transport.new({
      url: "https://foo.com/bar",
      retries: 3,
    })
    response = transport.send_batch(@batch)
    assert_equal 201, response.status
    assert_equal 2, attempts
    assert_nil response.error
    assert_equal 0, transport.backoff_policy.attempts
  end

  def test_send_batch_client_error
    [400, 404].each do |error_status_code|
      attempts = 0
      responder = -> (request) {
        attempts += 1
        {status: error_status_code}
      }
      stub_request(:post, "https://foo.com/bar").to_return(responder)

      transport = Brow::Transport.new({
        url: "https://foo.com/bar",
        retries: 2,
      })
      response = transport.send_batch(@batch)
      assert_equal error_status_code, response.status
      assert_equal 1, attempts # no retry
      assert_nil response.error
      assert_equal 0, transport.backoff_policy.attempts
    end
  end

  def test_response_parse_error
    attempts = 0
    responder = -> (request) {
      attempts += 1
      {status: 201, body: "<html>not json</html>"}
    }
    stub_request(:post, "https://foo.com/bar").to_return(responder)

    transport = Brow::Transport.new({
      url: "https://foo.com/bar",
      retries: 3,
    })
    response = transport.send_batch(@batch)
    assert_equal 201, response.status
    assert_equal 1, attempts
    assert_nil response.error
    assert_equal 0, transport.backoff_policy.attempts
  end
end
