module Brow
  # Internal: Wraps an existing logger and adds a prefix to all messages.
  class PrefixedLogger
    def initialize(logger, prefix)
      @logger = logger
      @prefix = prefix
    end

    def debug(message)
      @logger.debug("#{@prefix} #{message}")
    end

    def info(message)
      @logger.info("#{@prefix} #{message}")
    end

    def warn(message)
      @logger.warn("#{@prefix} #{message}")
    end

    def error(message)
      @logger.error("#{@prefix} #{message}")
    end
  end
end
