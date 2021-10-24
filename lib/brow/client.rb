# frozen_string_literal: true

require 'thread'
require 'time'

require_relative 'utils'
require_relative 'worker'
require_relative 'test_queue'

module Brow
  class Client
    # Private: Default # of items that can be in queue before we start dropping data.
    MAX_QUEUE_SIZE = 10_000

    # Public: Create a new instance of a client.
    #
    # options - The Hash of options.
    #   :max_queue_size - The maximum number of calls to be remain queued.
    #   :on_error - The Proc that handles error calls from the API.
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

    # Public: Synchronously waits until the worker has flushed the queue.
    #
    # Use only for scripts which are not long-running, and will
    # specifically exit.
    def flush
      while !@queue.empty? || @worker.requesting?
        ensure_worker_running
        sleep(0.1)
      end
    end

    # Public: Enqueues an event to eventually be transported to backend service.
    #
    # event - The Hash of event data.
    #
    # Returns Boolean of whether the item was added to the queue.
    def push(event)
      raise ArgumentError, "event must be a Hash" unless event.is_a?(Hash)

      event = Brow::Utils.symbolize_keys(event)
      event = Brow::Utils.isoify_dates(event)
      enqueue event
    end

    # Public: Returns the number of messages in the queue.
    def queued_messages
      @queue.length
    end

    # Public: For test purposes only. If test: true is passed to #initialize
    # then all pushing of events will go to test queue in memory so they can
    # be verified with assertions.
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
    def enqueue(item)
      if @test
        test_queue << item
        return true
      end

      if @queue.length < @max_queue_size
        @queue << item
        ensure_worker_running

        true
      else
        @logger.warn("[brow]") { "Queue is full, dropping events. The :max_queue_size configuration parameter can be increased to prevent this from happening." }
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
