# frozen_string_literal: true

require "json"

module Capsium
  class Reactor
    # Plain HTTP response writers shared by the reactor dispatch, the
    # route serving and the API handlers (data, GraphQL, save).
    module Responses
      private

      def respond_not_found(response) = respond_text(response, 404, "Not Found")

      def respond_forbidden(response) = respond_text(response, 403, "Forbidden")

      def respond_not_implemented(response) = respond_text(response, 501, "Not Implemented")

      def respond_method_not_allowed(response) = respond_text(response, 405, "Method Not Allowed")

      def respond_text(response, status, body)
        response.status = status
        response["Content-Type"] = "text/plain"
        response.body = body
      end

      def respond_json(response, status, body)
        response.status = status
        response["Content-Type"] = "application/json"
        response.body = JSON.generate(body)
      end

      # A JSON error body ("error" plus optional "messages" details) —
      # the shape the data/write APIs answer client errors with.
      def respond_error(response, status, message, messages: nil)
        body = { error: message }
        body[:messages] = messages if messages
        respond_json(response, status, body)
      end
    end
  end
end
