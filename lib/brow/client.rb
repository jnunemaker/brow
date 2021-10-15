# frozen_string_literal: true

require 'thread'
require 'time'

require 'brow/utils'
require 'brow/worker'
require 'brow/test_queue'

module Brow
  class Client
    # Default # of items that can be in queue before we start dropping data.
    MAX_QUEUE_SIZE = 10_000

    # Public: Create a new instance of a client.
    #
    # options - The Hash of options.
    #   :max_queue_size Maximum number of calls to be remain queued.
    #   :on_error The Proc that handles error calls from the API.
    def initialize(options = {})
      options = Brow::Utils.symbolize_keys(options)

      @worker_thread = nil
      @worker_mutex = Mutex.new
      @test = options[:test]
      @max_queue_size = options[:max_queue_size] || MAX_QUEUE_SIZE
      @logger = options.fetch(:logger) { Brow.logger }
      @queue = options.fetch(:queue) { Queue.new }
      @worker = options.fetch(:worker) { Worker.new(@queue, options) }

      at_exit { @worker_thread && @worker_thread[:should_exit] = true }
    end

    # Synchronously waits until the worker has flushed the queue.
    #
    # Use only for scripts which are not long-running, and will
    # specifically exit.
    def flush
      while !@queue.empty? || @worker.requesting?
        ensure_worker_running
        sleep(0.1)
      end
    end

    # Public: Enqueues the event.
    #
    # event - The Hash of event data.
    #
    # Returns Boolean of whether the item was added to the queue.
    def record(event)
      enqueue Brow::Utils.symbolize_keys(event)
    end

    # Public: Returns the number of messages in the queue.
    def queued_messages
      @queue.length
    end

    def test_queue
      unless @test
        raise 'Test queue only available when setting :test to true.'
      end

      @test_queue ||= TestQueue.new
    end

    private

    # Private: Enqueues the event.
    #
    # Returns Boolean of whether the item was added to the queue.
    def enqueue(action)
      if @test
        test_queue << action
        return true
      end

      if @queue.length < @max_queue_size
        @queue << action
        ensure_worker_running

        true
      else
        @logger.warn 'Queue is full, dropping events. The :max_queue_size configuration parameter can be increased to prevent this from happening.'
        false
      end
    end

    def ensure_worker_running
      return if worker_running?
      @worker_mutex.synchronize do
        return if worker_running?
        @worker_thread = Thread.new do
          @worker.run
        end
      end
    end

    def worker_running?
      @worker_thread && @worker_thread.alive?
    end
  end
end
