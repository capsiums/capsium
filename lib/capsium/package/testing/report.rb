# frozen_string_literal: true

module Capsium
  class Package
    module Testing
      # The outcome of a test suite run: one Result per test case.
      class Report
        attr_reader :results

        def initialize(results = [])
          @results = results
        end

        def <<(result)
          @results << result
          self
        end

        def ok?
          @results.all?(&:ok?)
        end

        def failures
          @results.reject(&:ok?)
        end

        def summary
          "#{@results.size} tests, #{failures.size} failures"
        end
      end
    end
  end
end
