# frozen_string_literal: true
require "pathname"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "brow"

require "minitest/autorun"
require "minitest/heat"

# Get rid of log output
Brow.logger = Logger.new("/dev/null")

# A worker that doesn't consume jobs
class NoopWorker
  def run
    # Does nothing
  end

  def requesting?
    false
  end
end

# A worker that consumes all jobs
class DummyWorker
  def initialize(queue)
    @queue = queue
  end

  def run
    @queue.pop until @queue.empty?
  end

  def requesting?
    false
  end
end
