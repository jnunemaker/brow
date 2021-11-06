# Usage: bundle exec ruby examples/echo_server.rb
#
# By default this starts in thread that other example scripts can use.
#
# By setting FOREGROUND=1, this will run in the foreground instead of
# background thread.
#
# FOREGROUND=1 bundle exec ruby examples/echo_server.rb
require "socket"
require "thread"
require "logger"
require "json"
require "singleton"
require "webrick"

class EchoServer
  include Singleton

  attr_reader :port, :thread

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @port = ENV.fetch("PORT", 9999)
    @started = false

    @server = WEBrick::HTTPServer.new({
      Port: @port,
      StartCallback: -> { @started = true },
      Logger: WEBrick::Log.new(@logger, WEBrick::Log::INFO),
      AccessLog: [
        [@logger, WEBrick::AccessLog::COMMON_LOG_FORMAT],
      ],
    })

    @server.mount_proc '/' do |request, response|
      @logger.debug JSON.parse(request.body).inspect
      response.header["Content-Type"] = "application/json"
      response.body = "{}"
    end

    @thread = Thread.new { @server.start }
    Timeout.timeout(10) { :wait until @started }
  end
end

EchoServer.instance

if ENV.fetch("FOREGROUND", "0") == "1"
  EchoServer.instance.thread.join
end
