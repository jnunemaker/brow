require "socket"
require "thread"
require "logger"
require "json"
require "rack"
require "rack/handler/webrick"

class EchoServer
  include Singleton

  attr_reader :port

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @port = ENV.fetch("PORT", 9999)
    builder = Rack::Builder.new
    builder.run ->(env) {
      request = Rack::Request.new(env)
      @logger.debug JSON.parse(request.body.read).inspect
      [200, {}, [""]]
    }
    @started = false

    @server = WEBrick::HTTPServer.new({
      Port: @port,
      StartCallback: -> { @started = true },
      Logger: WEBrick::Log.new(@logger, WEBrick::Log::INFO),
      AccessLog: [
        [@logger, WEBrick::AccessLog::COMMON_LOG_FORMAT],
      ],
    })
    @server.mount '/', Rack::Handler::WEBrick, builder

    @thread = Thread.new { @server.start }
    Timeout.timeout(10) { :wait until @started }
  end
end

EchoServer.instance
