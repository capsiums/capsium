# frozen_string_literal: true

module Capsium
  class Reactor
    # Minimal in-memory request counters for the /introspect/metrics
    # endpoint (07-reactor): total requests plus a breakdown by HTTP
    # status, thread-safe via Mutex (WEBrick serves concurrently).
    class Metrics
      def initialize
        @mutex = Mutex.new
        @total = 0
        @by_status = Hash.new(0)
      end

      def record(status)
        @mutex.synchronize do
          @total += 1
          @by_status[status.to_i] += 1
        end
        self
      end

      def snapshot
        @mutex.synchronize do
          { requestsTotal: @total, requestsByStatus: @by_status.dup }
        end
      end
    end
  end
end
