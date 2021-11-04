require "socket"
require "thread"
require "rack"
require "rack/handler/webrick"

class FakeServer
  attr_reader :port, :requests, :thread

  def initialize
    @started = false
    @requests = []
    @thread = Thread.new { server.start }
    Timeout.timeout(10) { :wait until @started }
  end

  def reset
    @requests.clear
  end

  def shutdown
    if thread
      server.shutdown
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
      server.mount '/', Rack::Handler::WEBrick, ->(env) {
        @requests << Rack::Request.new(env)
        [200, {}, [""]]
      }
      server
    end
  end
end
