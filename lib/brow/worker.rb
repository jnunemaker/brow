# frozen_string_literal: true

require_relative 'message_batch'
require_relative 'transport'
require_relative 'utils'

module Brow
  class Worker
    DEFAULT_ON_ERROR = proc { |status, error| }

    # Public: Creates a new worker
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
      @batch = options.fetch(:batch) { MessageBatch.new(max_size: options[:batch_size]) }
    end

    # Public: Continuously runs the loop to check for new events
    def run
      until Thread.current[:should_exit]
        return if @queue.empty?

        @lock.synchronize do
          consume_message_from_queue! until @batch.full? || @queue.empty?
        end

        response = @transport.send_batch @batch
        @on_error.call(response.status, response.error) unless response.status == 200

        @lock.synchronize { @batch.clear }
      end
    ensure
      @transport.shutdown
    end

    # Public: Check whether we have outstanding requests.
    def requesting?
      @lock.synchronize { !@batch.empty? }
    end

    private

    def consume_message_from_queue!
      @batch << @queue.pop
    rescue MessageBatch::JSONGenerationError => error
      @on_error.call(-1, error)
    end
  end
end
