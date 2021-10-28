# frozen_string_literal: true

require 'securerandom'
require 'forwardable'

module Brow
  # Internal: A batch of messages to be sent to the API.
  class MessageBatch
    extend Forwardable

    # Private: The error raised when a message cannot be serialized to json.
    class JSONGenerationError < ::Brow::Error; end

    # Private: Maximum bytes for an individual message.
    MAX_BYTES_PER_MESSAGE = 32_768 # 32Kb

    # Private: Maximum total bytes for a batch.
    MAX_BYTES = 512_000 # 500Kb

    # Private: Maximum number of messages in a batch.
    MAX_SIZE = 100

    def_delegators :@messages, :empty?
    def_delegators :@messages, :length
    def_delegators :@messages, :size
    def_delegators :@messages, :count

    attr_reader :uuid, :json_size

    def initialize(options = {})
      clear
      @max_size = options[:max_size] || MAX_SIZE
      @logger = options.fetch(:logger) { Brow.logger }
    end

    def <<(message)
      begin
        message_json = message.to_json
      rescue StandardError => error
        raise JSONGenerationError, "Serialization error: #{error}"
      end

      message_json_size = message_json.bytesize

      if message_too_big?(message_json_size)
        @logger.error("[brow]") { 'a message exceeded the maximum allowed size' }
      else
        @messages << message
        @json_size += message_json_size + 1 # One byte for the comma
      end
    end

    def full?
      item_count_exhausted? || size_exhausted?
    end

    def clear
      @messages = []
      @json_size = 0
      @uuid = SecureRandom.uuid
    end

    def as_json
      {
        uuid: @uuid,
        messages: @messages,
      }
    end

    def to_json
      JSON.generate(as_json)
    end

    private

    def item_count_exhausted?
      @messages.length >= @max_size
    end

    def message_too_big?(message_json_size)
      message_json_size > MAX_BYTES_PER_MESSAGE
    end

    # We consider the max size here as just enough to leave room for one more
    # message of the largest size possible. This is a shortcut that allows us
    # to use a native Ruby `Queue` that doesn't allow peeking. The tradeoff
    # here is that we might fit in less messages than possible into a batch.
    #
    # The alternative is to use our own `Queue` implementation that allows
    # peeking, and to consider the next message size when calculating whether
    # the message can be accomodated in this batch.
    def size_exhausted?
      @json_size >= (MAX_BYTES - MAX_BYTES_PER_MESSAGE)
    end
  end
end
