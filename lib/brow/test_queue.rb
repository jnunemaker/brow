# frozen_string_literal: true

module Brow
  # Public: The test queue to use if the `Client` is in test mode. Keeps all
  # messages in an array so you can add assertions.
  #
  # Be sure to reset before each test case.
  class TestQueue
    attr_reader :messages

    def initialize
      reset
    end

    def count
      messages.count
    end
    alias_method :size, :count
    alias_method :length, :count

    def <<(message)
      messages << message
    end

    def reset
      @messages = []
    end
  end
end
