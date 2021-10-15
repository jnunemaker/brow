# frozen_string_literal: true

module Brow
  module Utils
    extend self

    # Public: Return a new hash with keys converted from strings to symbols
    def symbolize_keys(hash)
      hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
      end
    end
  end
end
