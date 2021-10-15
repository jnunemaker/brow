# frozen_string_literal: true

require_relative "brow/version"
require "logger"

module Brow
  class Error < StandardError; end

  def self.logger
    return @logger if @logger

    base_logger = if defined?(Rails)
      Rails.logger
    else
      logger = Logger.new STDOUT
      logger.progname = 'brow'
      logger
    end

    @logger = base_logger
  end

  def self.logger=(new_logger)
    @logger = new_logger
  end
end

require_relative "brow/client"
