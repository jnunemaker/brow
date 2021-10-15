# frozen_string_literal: true
require "pathname"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "brow"

require "minitest/autorun"

# Get rid of log output
Brow.logger = Logger.new("/dev/null")
