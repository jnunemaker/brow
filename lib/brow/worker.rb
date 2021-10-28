# frozen_string_literal: true

require_relative 'message_batch'
require_relative 'transport'
require_relative 'utils'

module Brow
  # Internal: The Worker to pull items off the queue and put them
  class Worker
    DEFAULT_ON_ERROR = proc { |response| }
    SHUTDOWN = Object.new

    # Internal: Creates a new worker
    #
    # The worker continuously takes messages off the queue and makes requests to
    # the api.
    #
    # queue   - Queue synchronized between client and worker
    # options - The Hash of worker options.
    #           batch_size - Fixnum of how many items to send in a batch.
    #           on_error - Proc of what to do on an error.
    #           transport - The Transport object to deliver batches.
    #           logger - The Logger object for all log messages.
    #           batch - The MessageBatch to collect messages and deliver batches
    #                   via Transport.
    def initialize(queue, options = {})
      @queue = queue
      @lock = Mutex.new
      options = Brow::Utils.symbolize_keys(options)
      @on_error = options[:on_error] || DEFAULT_ON_ERROR
      @transport = options.fetch(:transport) { Transport.new(options) }
      @logger = options.fetch(:logger) { Brow.logger }
      @batch_size = options[:batch_size]
    end

    def shutdown
      @queue << SHUTDOWN
    end

    # Internal: Continuously runs the loop to check for new events
    def run
      batch = MessageBatch.new(max_size: @batch_size)

      loop do
        message = @queue.pop

        case message
        when SHUTDOWN
          send_batch(batch) unless batch.empty?
          break
        else
          begin
            batch << message
          rescue MessageBatch::JSONGenerationError => error
            @on_error.call(Response.new(-1, error))
          end

          send_batch(batch) if batch.full?
        end
      end
    ensure
      @transport.shutdown
    end

    private

    def send_batch(batch)
      response = @transport.send_batch(batch)

      unless response.status == 200
        @on_error.call(response)
      end

      response
    end
  end
end
