# frozen_string_literal: true

require_relative "brow/version"
require "logger"

module Brow
  class Error < StandardError; end

  # Private
  LOG_PREFIX = "[brow]"

  # Public: Returns the logger instance to use for logging of things.
  def self.logger
    return @logger if @logger

    @logger = if defined?(Rails)
      Rails.logger
    else
      Logger.new(STDOUT)
    end
  end

  # Public: Sets the logger instance to use for logging things.
  def self.logger=(new_logger)
    @logger = new_logger
  end
end

require_relative "brow/client"
