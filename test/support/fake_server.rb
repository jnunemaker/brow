require "socket"
require "thread"
require "webrick"

class FakeServer
  attr_reader :port, :requests, :thread

  class Request
    attr_reader :request_method, :path, :headers, :body

    def initialize(options = {})
      @request_method = options.fetch(:request_method)
      @path = options.fetch(:path)
      @headers = options.fetch(:headers)
      @body = options.fetch(:body)
    end
  end

  def initialize(&block)
    @started = false
    @requests = []
    @thread = Thread.new { server.start }
    Timeout.timeout(10) { :wait until @started }

    if block_given?
      begin
        yield(self)
      ensure
        shutdown
      end
    end
  end

  def shutdown
    if thread
      server.shutdown
      sleep 0.2
      # Webrick starts thread for request timeouts that doesn't get killed
      # in Server#shutdown.
      WEBrick::Utils::TimeoutHandler.terminate
      thread.kill
      thread.join
    end
  end

  private

  def server
    @server ||= begin
      @port ||= 10_001
      server_options = {
        Port: @port,
        StartCallback: -> { @started = true },
        Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::INFO),
        AccessLog: [[File::NULL, WEBrick::AccessLog::COMBINED_LOG_FORMAT]],
        RequestTimeout: 0.2,
      }
      server = begin
        WEBrick::HTTPServer.new(server_options)
      rescue Errno::EADDRINUSE
        p "#{@port} in use, trying next with #{@port + 1}"
        @port += 1
        server_options[:Port] = @port
        retry
      end

      server.mount_proc '/' do |req, res|
        headers = {}
        req.each { |k, v| headers[k] = v }
        @requests << Request.new({
          request_method: req.request_method,
          path: req.path,
          body: req.body,
          headers: headers,
        })
      end

      server
    end
  end
end
