# frozen_string_literal: true

require "net/http"
require "uri"

module Capsium
  class Package
    module Testing
      # A "route" test (05x-testing): requests the URL path from the
      # reactor serving the package and checks the expected status, and
      # optionally the content type and a response body substring.
      class RouteTest < TestCase
        attr_reader :url, :expected_status, :response_contains, :expected_content_type

        def initialize(name:, url:, expected_status:, response_contains: nil,
                       expected_content_type: nil)
          super(name: name)
          @url = url
          @expected_status = expected_status
          @response_contains = response_contains
          @expected_content_type = expected_content_type
        end

        def run(context)
          response = Net::HTTP.get_response(URI.join(context.base_url, request_path))
          problems = status_problems(response) + content_type_problems(response) +
                     body_problems(response)
          Result.new(name: name, ok: problems.empty?, messages: problems)
        end

        private

        # The DSL allows absolute URLs; only their path (and query) is
        # used — the runner always targets its own reactor.
        def request_path
          uri = URI.parse(url)
          uri.host ? uri.request_uri : url
        end

        def status_problems(response)
          return [] if response.code.to_i == expected_status

          ["expected status #{expected_status}, got #{response.code}"]
        end

        def content_type_problems(response)
          return [] unless expected_content_type
          return [] if response.content_type == expected_content_type

          ["expected content type #{expected_content_type}, got #{response.content_type}"]
        end

        def body_problems(response)
          return [] unless response_contains
          return [] if response.body.to_s.include?(response_contains)

          ["response does not contain #{response_contains.inspect}"]
        end
      end

      TestCase.register("route", RouteTest)
    end
  end
end
