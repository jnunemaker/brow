# frozen_string_literal: true

module Brow
  class Response
    attr_reader :status, :error

    # Public: Simple class to wrap responses from the API
    def initialize(status = 200, error = nil)
      @status = status
      @error  = error
    end
  end
end
