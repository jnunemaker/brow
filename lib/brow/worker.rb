# frozen_string_literal: true

require 'thread'

require_relative 'message_batch'
require_relative 'transport'
require_relative 'utils'

module Brow
  # Internal: The Worker to pull items off the queue and put them
  class Worker
    # Private: Noop default on error proc.
    DEFAULT_ON_ERROR = proc { |response| }

    # Private: Object to enqueue to signal shutdown for worker.
    SHUTDOWN = :__ಠ_ಠ__

    # Private: Default number of seconds to wait to shutdown worker thread.
    SHUTDOWN_TIMEOUT = 5

    # Private: Default # of items that can be in queue before we start dropping data.
    MAX_QUEUE_SIZE = 10_000

    # Private
    attr_reader :thread, :queue, :pid, :mutex, :on_error, :batch_size, :max_queue_size

    # Private
    attr_reader :logger, :transport, :shutdown_timeout

    # Internal: Creates a new worker
    #
    # The worker continuously takes messages off the queue and makes requests to
    # the api.
    #
    # options - The Hash of worker options.
    #   :queue - Queue synchronized between client and worker
    #   :on_error - Proc of what to do on an error.
    #   :batch_size - Fixnum of how many items to send in a batch.
    #   :transport - The Transport object to deliver batches.
    #   :logger - The Logger object for all log messages.
    #   :batch - The MessageBatch to collect messages and deliver batches
    #            via Transport.
    #   :shutdown_timeout - The number of seconds to wait for the worker thread
    #                       to join when shutting down.
    #   :start_automatically - Should the client start the worker thread
    #                          automatically and keep it running.
    #   :shutdown_automatically - Should the client shutdown automatically or
    #                             manually. If true, shutdown is automatic. If
    #                             false, you'll need to handle this on your own.
    def initialize(options = {})
      @thread = nil
      @queue = options.fetch(:queue) { Queue.new }
      @pid = Process.pid
      @mutex = Mutex.new
      options = Brow::Utils.symbolize_keys(options)
      @on_error = options[:on_error] || DEFAULT_ON_ERROR
      @logger = options.fetch(:logger) { Brow.logger }
      @transport = options.fetch(:transport) { Transport.new(options) }

      @batch_size = options.fetch(:batch_size) {
        ENV.fetch("BROW_BATCH_SIZE", MessageBatch::MAX_SIZE).to_i
      }
      @max_queue_size = options.fetch(:max_queue_size) {
        ENV.fetch("BROW_MAX_QUEUE_SIZE", MAX_QUEUE_SIZE).to_i
      }
      @shutdown_timeout = options.fetch(:shutdown_timeout) {
        ENV.fetch("BROW_SHUTDOWN_TIMEOUT", SHUTDOWN_TIMEOUT).to_f
      }

      if @batch_size <= 0
        raise ArgumentError, ":batch_size must be greater than 0"
      end

      if @max_queue_size <= 0
        raise ArgumentError, ":max_queue_size must be greater than 0"
      end

      if @shutdown_timeout <= 0
        raise ArgumentError, ":shutdown_timeout must be greater than 0"
      end

      @start_automatically = options.fetch(:start_automatically, true)

      if options.fetch(:shutdown_automatically, true)
        at_exit { stop }
      end
    end

    def push(data)
      raise ArgumentError, "data must be a Hash" unless data.is_a?(Hash)
      start if @start_automatically

      data = Utils.isoify_dates(data)

      if queue.length < max_queue_size
        queue << data
        true
      else
        logger.warn { "[brow] Queue is full, dropping events. The :max_queue_size configuration parameter can be increased to prevent this from happening." }
        false
      end
    end

    def start
      reset if forked?
      ensure_worker_running
    end

    def stop
      queue << SHUTDOWN

      if @thread
        begin
          if @thread.join(shutdown_timeout)
            logger.info { "[brow] Worker thread [#{@thread.object_id}] joined sucessfully" }
          else
            logger.info { "[brow] Worker thread [#{@thread.object_id}] did not join successfully" }
          end
        rescue => error
          logger.info { "[brow] Worker thread [#{@thread.object_id}] error shutting down: #{error.inspect}" }
        end
      end
    end

    # Internal: Continuously runs the loop to check for new events
    def run
      batch = MessageBatch.new(max_size: batch_size)

      loop do
        message = queue.pop

        case message
        when SHUTDOWN
          logger.info { "[brow] Worker shutting down" }
          send_batch(batch) unless batch.empty?
          break
        else
          begin
            batch << message
          rescue MessageBatch::JSONGenerationError => error
            on_error.call(Response.new(-1, error))
          end

          send_batch(batch) if batch.full?
        end
      end
    ensure
      transport.shutdown
    end

    private

    def forked?
      pid != Process.pid
    end

    def ensure_worker_running
      # Return early if thread is alive and avoid the mutex lock and unlock.
      return if thread_alive?

      # If another thread is starting worker thread, then return early so this
      # thread can enqueue and move on with life.
      return unless mutex.try_lock

      begin
        return if thread_alive?
        @thread = Thread.new { run }
        logger.debug { "[brow] Worker thread [#{@thread.object_id}] started" }
      ensure
        mutex.unlock
      end
    end

    def thread_alive?
      @thread && @thread.alive?
    end

    def reset
      @pid = Process.pid
      mutex.unlock if mutex.locked?
      queue.clear
    end

    def send_batch(batch)
      response = transport.send_batch(batch)

      unless response.status == 200
        on_error.call(response)
      end

      response
    end
  end
end
