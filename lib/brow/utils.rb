# frozen_string_literal: true

require 'time'

module Brow
  module Utils
    extend self

    # Internal: Return a new hash with keys converted from strings to symbols
    def symbolize_keys(hash)
      hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
      end
    end

    # Internal: Returns a new hash with all the date values in the into
    # iso8601 strings
    def isoify_dates(hash)
      hash.each_with_object({}) do |(k, v), memo|
        memo[k] = datetime_in_iso8601(v)
      end
    end

    # Internal
    def datetime_in_iso8601(datetime)
      case datetime
      when Time
        time_in_iso8601 datetime
      when DateTime
        time_in_iso8601 datetime.to_time
      when Date
        date_in_iso8601 datetime
      else
        datetime
      end
    end

    # Internal
    def time_in_iso8601(time)
      "#{time.strftime('%Y-%m-%dT%H:%M:%S.%6N')}#{formatted_offset(time, true, 'Z')}"
    end

    # Internal
    def date_in_iso8601(date)
      date.strftime('%F')
    end

    # Internal
    def formatted_offset(time, colon = true, alternate_utc_string = nil)
      time.utc? && alternate_utc_string || seconds_to_utc_offset(time.utc_offset, colon)
    end

    # Internal
    def seconds_to_utc_offset(seconds, colon = true)
      (colon ? UTC_OFFSET_WITH_COLON : UTC_OFFSET_WITHOUT_COLON) % [(seconds < 0 ? '-' : '+'), (seconds.abs / 3600), ((seconds.abs % 3600) / 60)]
    end

    # Internal
    UTC_OFFSET_WITH_COLON = '%s%02d:%02d'

    # Internal
    UTC_OFFSET_WITHOUT_COLON = UTC_OFFSET_WITH_COLON.sub(':', '')
  end
end
