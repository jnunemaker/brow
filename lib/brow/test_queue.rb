# frozen_string_literal: true

module Brow
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
