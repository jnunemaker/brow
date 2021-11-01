# frozen_string_literal: true
require "pathname"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "brow"

require "climate_control"
require "maxitest/autorun"
require "maxitest/timeout"
require "maxitest/threads"
require "minitest/heat"
require "webmock/minitest"
require_relative "support/fake_server"

# Timeout tests that get stuck in worker loop or that take too long.
Maxitest.timeout = 10

# Setup webmock to allow localhost so we can hit the fake test server.
WebMock.disable_net_connect!(allow_localhost: true)

# Get rid of log output
Brow.logger = Logger.new("/dev/null")

# Fake transport that does nothing but succeed.
class NoopTransport
  def send_batch(*)
    Brow::Response.new(200, "Success")
  end

  def shutdown(*)
  end
end

module ClimateControlHelpers
  def with_modified_env(options, &block)
    ClimateControl.modify(options, &block)
  end
end

Minitest::Test.send :include, ClimateControlHelpers
