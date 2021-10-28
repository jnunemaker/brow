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

    # Private: Default number of seconds to wait to shutdown worker thread.
    SHUTDOWN_TIMEOUT = 5

    # Private
    attr_reader :pid, :test, :max_queue_size, :logger, :queue, :worker, :shutdown_timeout

    # Public: Create a new instance of a client.
    #
    # options - The Hash of options.
    #   :url - The URL where all batches of data should be transported.
    #   :test - Should the client be in test mode. If true, all data is stored
    #           in memory for later verification in a test. If false, things
    #           work as normal.
    #   :max_queue_size - The maximum number of calls to be remain queued.
    #   :logger - The Logger to use to log useful information about what is
    #             going on.
    #   :queue - The Queue to use to store data until it can be batched up and
    #            transported to the API.
    #   :worker - The Worker that will pop items off the queue, batch them up
    #             and transport them to the API.
    #   :transport - The Transport to use to transport batches to the API.
    #   :headers - The Hash of headers to include when transporting batches to
    #              the API. These could be used for auth or whatever.
    #   :retries - The Integer number of times the transport should retry a call
    #              before giving up.
    #   :read_timeout - The number of seconds to wait when reading data before
    #                   giving up.
    #   :open_timeout - The number of seconds to wait when opening a connection
    #                   to the API.
    #   :backoff_policy - The BackoffPolicy to use to determine when the next
    #                     retry should occur when the transport fails to send a
    #                     batch of data to the API.
    #   :min_timeout_ms - The minimum number of milliseconds to wait before
    #                     retrying a failed call to the API.
    #   :max_timeout_ms - The maximum number of milliseconds to wait before
    #                     retrying a failed call to the API.
    #   :multiplier - The value to multily the current interval with for each
    #                 retry attempt.
    #   :randomization_factor - The value to use to create a range of jitter
    #                 around the retry interval.
    #   :batch - The MessageBatch used to batch up several events to be
    #            transported in one call to the API.
    #   :max_size - The maximum number of items a batch can contain before it
    #               should be transported to the API. Only used if not :batch
    #               is provided.
    #   :shutdown_timeout - The number of seconds to wait for the worker thread
    #                       to join when shutting down.
    #   :shutdown_automatically - Should the client shutdown automatically or
    #                             manually. If true, shutdown is automatic. If
    #                             false, you'll need to handle this on your own.
    #   :on_error - The Proc that handles error calls from the API.
    def initialize(options = {})
      options = Brow::Utils.symbolize_keys(options)

      @worker_thread = nil
      @pid = Process.pid
      @test = options[:test]
      @max_queue_size = options[:max_queue_size] || MAX_QUEUE_SIZE
      @logger = options.fetch(:logger) { Brow.logger }
      @queue = options.fetch(:queue) { Queue.new }
      @worker = options.fetch(:worker) { Worker.new(queue, options) }
      @shutdown_timeout = options.fetch(:shutdown_timeout) { SHUTDOWN_TIMEOUT }

      if options.fetch(:shutdown_automatically, true)
        at_exit { shutdown }
      end
    end

    def shutdown
      worker.shutdown

      if @worker_thread
        begin
          if @worker_thread.join(@shutdown_timeout)
            @logger.info("[brow]") { "Worker thread [#{@worker_thread.object_id}] joined sucessfully" }
          else
            @logger.info("[brow]") { "Worker thread [#{@worker_thread.object_id}] did not join successfully" }
          end
        rescue => error
          @logger.info("[brow]") { "Worker thread [#{@worker_thread.object_id}] error shutting down: #{error.inspect}" }
        end
      end
    end

    # Public: Enqueues an event to eventually be transported to backend service.
    #
    # data - The Hash of data.
    #
    # Returns Boolean of whether the data was added to the queue.
    def push(data)
      raise ArgumentError, "data must be a Hash" unless data.is_a?(Hash)

      data = Brow::Utils.symbolize_keys(data)
      data = Brow::Utils.isoify_dates(data)

      if @test
        test_queue << data
        return true
      end

      ensure_threads_alive

      if @queue.length < @max_queue_size
        @queue << data
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
      return unless worker.mutex.try_lock

      begin
        return if worker_running?
        @worker_thread = Thread.new { worker.run }
        @logger.debug("[brow]") { "Worker thread [#{@worker_thread.object_id}] started" }
      ensure
        @worker.mutex.unlock
      end
    end

    def reset
      @pid = Process.pid
      @worker.mutex.unlock if @worker.mutex.locked?
      @queue.clear
    end

    def worker_running?
      @worker_thread && @worker_thread.alive?
    end
  end
end
