# frozen_string_literal: true

require 'net/http'
require 'net/https'
require 'json'

require_relative 'response'
require_relative 'backoff_policy'

module Brow
  class Transport
    # Private: Default number of times to retry request.
    RETRIES = 10

    # Private: Default read timeout on requests.
    READ_TIMEOUT = 8

    # Private: Default open timeout on requests.
    OPEN_TIMEOUT = 4

    # Private
    attr_reader :url, :headers, :retries, :logger, :backoff_policy, :http

    def initialize(options = {})
      @url = options[:url] || raise(ArgumentError, ":url is required to be present so we know where to send batches")
      @uri = URI.parse(@url)

      # Default path if people forget a slash.
      if @uri.path.nil? || @uri.path.empty?
        @uri.path = "/"
      end

      @headers = options[:headers] || {}
      @retries = options[:retries] || RETRIES

      @logger = options.fetch(:logger) { Brow.logger }
      @backoff_policy = options.fetch(:backoff_policy) {
        Brow::BackoffPolicy.new(options)
      }

      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == "https"
      @http.read_timeout = options[:read_timeout] || READ_TIMEOUT
      @http.open_timeout = options[:open_timeout] || OPEN_TIMEOUT
    end

    # Sends a batch of messages to the API
    #
    # @return [Response] API response
    def send_batch(batch)
      logger.debug("[brow]") { "Sending request for #{batch.length} items" }

      last_response, exception = retry_with_backoff(retries) do
        response = send_request(batch)
        logger.debug("[brow]") { "Response: status=#{response.code}, body=#{response.body}" }
        [Response.new(response.code.to_i, nil), retry?(response)]
      end

      if exception
        logger.error("[brow]") { exception.message }
        exception.backtrace.each { |line| logger.error(line) }
        Response.new(-1, exception.to_s)
      else
        last_response
      end
    ensure
      backoff_policy.reset
      batch.clear
    end

    # Closes a persistent connection if it exists
    def shutdown
      logger.info("[brow]") { "Transport shutting down" }
      @http.finish if @http.started?
    end

    private

    def retry?(response)
      status_code = response.code.to_i
      if status_code >= 500
        # Server error. Retry and log.
        logger.info("[brow]") { "Server error: status=#{status_code}, body=#{response.body}" }
        true
      elsif status_code == 429
        # Rate limited. Retry and log.
        logger.info("[brow]") { "Rate limit error: body=#{response.body}" }
        true
      elsif status_code >= 400
        # Client error. Do not retry, but log.
        logger.error("[brow]") { "Client error: status=#{status_code}, body=#{response.body}" }
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
        logger.debug("[brow]") {  "Request error: #{error}" }
        should_retry = true
        caught_exception = error
      end

      if should_retry && (retries_remaining > 1)
        logger.debug("[brow]") { "Retrying request, #{retries_remaining} retries left" }
        sleep(@backoff_policy.next_interval.to_f / 1000)
        retry_with_backoff(retries_remaining - 1, &block)
      else
        [result, caught_exception]
      end
    end

    def send_request(batch)
      headers = {
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "User-Agent" => "brow-ruby/#{Brow::VERSION}",
        "Client-Language" => "ruby",
        "Client-Language-Version" => "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
        "Client-Platform" => RUBY_PLATFORM,
        "Client-Engine" => defined?(RUBY_ENGINE) ? RUBY_ENGINE : "",
        "Client-Hostname" => Socket.gethostname,
        "Client-Pid" => Process.pid.to_s,
        "Client-Thread" => Thread.current.object_id.to_s,
      }.merge(@headers)

      @http.start unless @http.started?
      request = Net::HTTP::Post.new(@uri.path, headers)
      @http.request(request, batch.to_json)
    end
  end
end
