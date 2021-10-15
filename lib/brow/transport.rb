# frozen_string_literal: true

require 'brow/response'
require 'brow/backoff_policy'
require 'net/http'
require 'net/https'
require 'json'

module Brow
  class Transport
    HOST = 'requestbin.net'
    PORT = 443
    PATH = '/r/gpj4ybzc'
    SSL = true
    RETRIES = 10
    HEADERS = {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json',
      'User-Agent' => "brow-ruby/#{Brow::VERSION}",
    }

    class << self
      attr_writer :stub

      def stub
        @stub || ENV['STUB']
      end
    end

    def initialize(options = {})
      @host = options[:host] || HOST
      @port = options[:port] || PORT
      @ssl = options[:ssl] || SSL
      @headers = options[:headers] || HEADERS
      @path = options[:path] || PATH

      @retries = options[:retries] || RETRIES
      @read_timeout = options[:read_timeout] || 8
      @open_timeout = options[:open_timeout] || 4

      @logger = options.fetch(:logger) { Brow.logger }
      @backoff_policy = options.fetch(:backoff_policy) { Brow::BackoffPolicy.new }

      @http = Net::HTTP.new(@host, @port)
      @http.use_ssl = @ssl
      @http.read_timeout = @read_timeout
      @http.open_timeout = @open_timeout
    end

    # Sends a batch of messages to the API
    #
    # @return [Response] API response
    def send_batch(batch)
      @logger.debug("Sending request for #{batch.length} items")

      last_response, exception = retry_with_backoff(@retries) do
        status_code, body = send_request(batch)
        error = begin
          json = JSON.parse(body)
          json ? json['error'] : nil
        rescue JSON::ParserError
          nil
        end
        should_retry = should_retry_request?(status_code, body)
        @logger.debug("Response status code: #{status_code}")
        @logger.debug("Response error: #{error}") if error

        [Response.new(status_code, error), should_retry]
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
        true # Server error
      elsif status_code == 429
        true # Rate limited
      elsif status_code >= 400
        @logger.error(body)
        false # Client error. Do not retry, but log
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
      rescue StandardError => e
        should_retry = true
        caught_exception = e
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
      payload = JSON.generate({
        id: batch.uuid,
        messages: batch,
      })

      if self.class.stub
        @logger.debug "stubbed request to #{@path}: body=#{payload}"

        [200, '{}']
      else
        @http.start unless @http.started? # Maintain a persistent connection
        request = Net::HTTP::Post.new(@path, @headers)
        response = @http.request(request, payload)
        [response.code.to_i, response.body]
      end
    end
  end
end
