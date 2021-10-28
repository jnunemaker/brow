require "test_helper"

class BrowTransportTest < Minitest::Test
  def setup
    @batch = Brow::MessageBatch.new.tap { |b| b << {n: 1}}
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
    transport_headers = transport.headers

    # includes defaults that weren't overwritten
    assert_equal "brow-ruby/#{Brow::VERSION}", transport_headers.fetch("User-Agent")
    assert_equal "ruby", transport_headers.fetch("Client-Language")
    assert_equal "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
      transport_headers.fetch("Client-Language-Version")

    assert_equal RUBY_PLATFORM, transport_headers.fetch("Client-Platform")
    assert_equal RUBY_ENGINE, transport_headers.fetch("Client-Engine")
    refute_nil transport_headers["Client-Hostname"]

    # overwrites default headers if provided
    assert_equal "text/plain", transport_headers.fetch("Accept")
    assert_equal "text/plain", transport_headers.fetch("Content-Type")

    # adds new headers
    assert_equal "asdf", transport_headers.fetch("Some-Token")

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

    assert_requested :post, "https://foo.com/"
  end

  def test_send_batch
    stub_request(:post, "https://foo.com/bar")
      .with({
        headers: {
          "Accept" => "application/json",
          "Content-Type" => "application/json",
          "User-Agent" => "brow-ruby/#{Brow::VERSION}",
        },
        body: @batch.to_json,
      })
      .to_return(status: 201)

    transport = Brow::Transport.new(url: "https://foo.com/bar")
    response = transport.send_batch(@batch)
    assert_equal 201, response.status
    assert_nil response.error

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
  end
end
