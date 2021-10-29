# frozen_string_literal: true

require 'time'

require_relative 'utils'
require_relative 'worker'

module Brow
  class Client
    # Public: Create a new instance of a client.
    #
    # options - The Hash of options.
    #   :url - The URL where all batches of data should be transported.
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
    #   :shutdown_timeout - The number of seconds to wait for the worker thread
    #                       to join when shutting down.
    #   :shutdown_automatically - Should the worker shutdown automatically or
    #                             manually. If true, shutdown is automatic. If
    #                             false, you'll need to handle this on your own.
    #   :max_size - The maximum number of items a batch can contain before it
    #               should be transported to the API. Only used if not :batch
    #               is provided.
    #   :on_error - The Proc that handles error calls from the API.
    def initialize(options = {})
      options = Brow::Utils.symbolize_keys(options)
      @worker = options.fetch(:worker) { Worker.new(options) }
    end

    # Private
    attr_reader :worker

    # Public: Enqueues an event to eventually be transported to backend service.
    #
    # data - The Hash of data.
    #
    # Returns Boolean of whether the data was added to the queue.
    def push(data)
      worker.push(data)
    end
  end
end
