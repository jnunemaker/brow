# frozen_string_literal: true

module Brow
  class TestQueue
    attr_reader :messages

    def initialize
      reset
    end

    def [](key)
      messages[key]
    end

    def count
      messages.count
    end

    def <<(message)
      messages << message
    end

    def reset
      @messages = []
    end
  end
end
