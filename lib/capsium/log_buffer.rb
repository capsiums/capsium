# frozen_string_literal: true

require "time"

module Capsium
  # A small thread-safe ring buffer of timestamped log entries with a
  # fixed capacity: when full, the oldest entry is dropped. The reactor
  # records key serving events here and exposes the most recent lines
  # through the /package/:id/logs introspection endpoint.
  class LogBuffer
    DEFAULT_CAPACITY = 500

    # One buffer entry: a UTC timestamp and a message.
    Entry = Data.define(:timestamp, :message) do
      # "2026-07-19T15:00:00Z message"
      def line = "#{timestamp.utc.iso8601} #{message}"
    end

    attr_reader :capacity

    def initialize(capacity: DEFAULT_CAPACITY)
      raise ArgumentError, "capacity must be at least 1" if capacity < 1

      @capacity = capacity
      @entries = []
      @mutex = Mutex.new
    end

    def add(message, timestamp: Time.now)
      @mutex.synchronize do
        @entries.shift if @entries.size >= @capacity
        @entries << Entry.new(timestamp: timestamp, message: message)
      end
      self
    end

    # The last count entries, oldest first.
    def last(count)
      @mutex.synchronize { @entries.last(count) }
    end

    # The last count entries as formatted lines, oldest first.
    def lines(count)
      last(count).map(&:line)
    end
  end
end
