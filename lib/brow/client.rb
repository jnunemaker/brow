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
      @pid = Process.pid
      @test = options[:test]
      @max_queue_size = options[:max_queue_size] || MAX_QUEUE_SIZE
      @logger = options.fetch(:logger) { Brow.logger }
      @queue = options.fetch(:queue) { Queue.new }
      @worker = options.fetch(:worker) { Worker.new(@queue, options) }
      @shutdown_timeout = options.fetch(:shutdown_timeout) { 5 }

      if options.fetch(:shutdown_automatically, true)
        at_exit { shutdown }
      end
    end

    # Public: Synchronously waits until the worker has flushed the queue.
    #
    # Use only for scripts which are not long-running, and will
    # specifically exit.
    def flush
      while !@queue.empty? || @worker.requesting?
        ensure_threads_alive
        sleep(0.1)
      end
    end

    def shutdown
      if @worker_thread
        begin
          @worker_thread.join @shutdown_timeout
        rescue => error
          @logger.info("[brow]") { "Error shutting down: #{error.inspect}"}
        end
      end
    end

    # Public: Enqueues an event to eventually be transported to backend service.
    #
    # event - The Hash of event data.
    #
    # Returns Boolean of whether the item was added to the queue.
    def push(item)
      raise ArgumentError, "item must be a Hash" unless item.is_a?(Hash)

      item = Brow::Utils.symbolize_keys(item)
      item = Brow::Utils.isoify_dates(item)

      if @test
        test_queue << item
        return true
      end

      ensure_threads_alive

      if @queue.length < @max_queue_size
        @queue << item
        true
      else
        @logger.warn("[brow]") { "Queue is full, dropping events. The :max_queue_size configuration parameter can be increased to prevent this from happening." }
        false
      end
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

    def forked?
      @pid != Process.pid
    end

    def ensure_threads_alive
      reset if forked?
      ensure_worker_running
    end

    def ensure_worker_running
      # If another thread is starting worker thread, then return early so this
      # thread can enqueue and move on with life.
      return unless @worker_mutex.try_lock

      begin
        return if worker_running?
        @worker_thread = Thread.new { @worker.run }
      ensure
        @worker_mutex.unlock
      end
    end

    def reset
      @pid = Process.pid
      @worker_mutex.unlock if @worker_mutex.locked?
      @queue.clear
    end

    def worker_running?
      @worker_thread && @worker_thread.alive?
    end
  end
end
