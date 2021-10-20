module Brow
  # Wraps an existing logger and adds a prefix to all messages
  class PrefixedLogger
    def initialize(logger, prefix)
      @logger = logger
      @prefix = prefix
    end

    def debug(msg)
      @logger.debug("#{@prefix} #{msg}")
    end

    def info(msg)
      @logger.info("#{@prefix} #{msg}")
    end

    def warn(msg)
      @logger.warn("#{@prefix} #{msg}")
    end

    def error(msg)
      @logger.error("#{@prefix} #{msg}")
    end
  end
end
