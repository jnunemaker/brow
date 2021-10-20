# frozen_string_literal: true

require 'net/http'
require 'net/https'
require 'json'

require_relative 'response'
require_relative 'backoff_policy'

module Brow
  class Transport
    RETRIES = 10
    HEADERS = {
      "Accept" => "application/json",
      "Content-Type" => "application/json",
      "User-Agent" => "brow-ruby/#{Brow::VERSION}",
      "Client-Language" => "ruby",
      "Client-Language-Version" => "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
      "Client-Platform" => RUBY_PLATFORM,
      "Client-Engine" => defined?(RUBY_ENGINE) ? RUBY_ENGINE : "",
      "Client-Pid" => Process.pid.to_s,
      "Client-Thread" => Thread.current.object_id.to_s,
      "Client-Hostname" => Socket.gethostname,
    }

    attr_reader :url

    def initialize(options = {})
      @url = options[:url] || raise(ArgumentError, ":url is required to be present so we know where to send batches")
      @uri = URI.parse(@url)

      # Default path if people forget a slash.
      if @uri.path.nil? || @uri.path.empty?
        @uri.path = "/"
      end

      @headers = HEADERS.merge(options[:headers] || {})
      @retries = options[:retries] || RETRIES

      @logger = options.fetch(:logger) { Brow.logger }
      @backoff_policy = options.fetch(:backoff_policy) {
        Brow::BackoffPolicy.new
      }

      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == "https"
      @http.read_timeout = options[:read_timeout] || 8
      @http.open_timeout = options[:open_timeout] || 4
    end

    # Sends a batch of messages to the API
    #
    # @return [Response] API response
    def send_batch(batch)
      @logger.debug("Sending request for #{batch.length} items")

      last_response, exception = retry_with_backoff(@retries) do
        response = send_request(batch)
        status_code = response.code.to_i
        should_retry = should_retry_request?(status_code, response.body)
        @logger.debug("Response status code: #{status_code}")

        [Response.new(status_code, nil), should_retry]
      end

      if exception
        @logger.error(exception.message)
        exception.backtrace.each { |line| @logger.error(line) }
        Response.new(-1, exception.to_s)
      else
        last_response
      end
    end

    # Closes a persistent connection if it exists
    def shutdown
      @http.finish if @http.started?
    end

    private

    def should_retry_request?(status_code, body)
      if status_code >= 500
        # Server error. Retry and log.
        @logger.info("Server error: status=#{status_code}, body=#{body}")
        true
      elsif status_code == 429
        # Rate limited
        @logger.info "Rate limit error"
        true
      elsif status_code >= 400
        # Client error. Do not retry, but log.
        @logger.error("Client error: status=#{status_code}, body=#{body}")
        false
      else
        false
      end
    end

    # Takes a block that returns [result, should_retry].
    #
    # Retries upto `retries_remaining` times, if `should_retry` is false or
    # an exception is raised. `@backoff_policy` is used to determine the
    # duration to sleep between attempts
    #
    # Returns [last_result, raised_exception]
    def retry_with_backoff(retries_remaining, &block)
      result, caught_exception = nil
      should_retry = false

      begin
        result, should_retry = yield
        return [result, nil] unless should_retry
      rescue StandardError => error
        @logger.debug "Request error: #{error}"
        should_retry = true
        caught_exception = error
      end

      if should_retry && (retries_remaining > 1)
        @logger.debug("Retrying request, #{retries_remaining} retries left")
        sleep(@backoff_policy.next_interval.to_f / 1000)
        retry_with_backoff(retries_remaining - 1, &block)
      else
        [result, caught_exception]
      end
    end

    # Sends a request for the batch, returns [status_code, body]
    def send_request(batch)
      payload = batch.to_json
      @http.start unless @http.started? # Maintain a persistent connection
      request = Net::HTTP::Post.new(@uri.path, @headers)
      @http.request(request, payload)
    end
  end
end
