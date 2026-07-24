# frozen_string_literal: true

require "json"

module Capsium
  class Reactor
    # REST CRUD over a mount's datasets (ARCHITECTURE.md sections 5 and
    # 5a): JSON item append/read/replace/delete against the overlay-
    # merged collection. Writes go only to the mount's writable overlay;
    # the immutable package never changes on disk.
    class DataApi
      include Responses

      autoload :CollectionQuery, "capsium/reactor/data_api/collection_query"

      PREFIX = "/api/v1/data/"
      COLLECTION_PATTERN = %r{\A/api/v1/data/(?<dataset>[^/]+)\z}
      ITEM_PATTERN = %r{\A/api/v1/data/(?<dataset>[^/]+)/(?<id>[^/]+)\z}

      def self.path?(inner_path)
        inner_path.start_with?(PREFIX)
      end

      def initialize(mount)
        @mount = mount
      end

      # The declared dataset route a data path addresses (the collection
      # route, also for item paths), or nil when the package does not
      # route this dataset — undeclared datasets are not served.
      def route_for(inner_path)
        match = COLLECTION_PATTERN.match(inner_path) || ITEM_PATTERN.match(inner_path)
        return nil unless match

        route = @mount.routes.resolve("#{PREFIX}#{match[:dataset]}")
        route if route&.dataset == match[:dataset]
      end

      def handle(inner_path, request, response)
        route = route_for(inner_path)
        return respond_not_found(response) unless route

        dataset = @mount.package.storage.dataset(route.dataset)
        return respond_not_found(response) unless dataset

        collection = COLLECTION_PATTERN.match(inner_path)
        if collection
          handle_collection(dataset, request, response)
        else
          handle_item(dataset, ITEM_PATTERN.match(inner_path)[:id], request, response)
        end
      end

      private

      def handle_collection(dataset, request, response)
        case request.request_method
        when "GET" then read_collection(dataset, request, response)
        when "POST" then append_item(dataset, request, response)
        else respond_method_not_allowed(response, allow: "GET, POST")
        end
      end

      def read_collection(dataset, request, response)
        query = CollectionQuery.from_query(query_hash(request))
        result = @mount.overlay.query_collection(dataset, query)
        return respond_not_modified(response) if etag_match?(request, result[:etag])

        response["ETag"] = result[:etag]
        response["X-Total-Count"] = result[:total].to_s
        respond_json(response, 200, result[:items])
      end

      # WEBrick HTTPRequest#query returns a Hash with string keys (and
      # values that may be multi-valued via WEBrick::HTTPUtils::FormData).
      # For unit-test ergonomics, accept any hash-like object.
      def query_hash(request)
        query = request.respond_to?(:query) ? request.query : nil
        return nil unless query.is_a?(Hash)

        query.transform_values(&:to_s)
      end

      def etag_match?(request, etag)
        return false unless etag

        incoming = request["If-None-Match"] rescue nil # rubocop:disable Style/RescueModifier
        incoming && incoming == etag
      end

      def handle_item(dataset, id, request, response)
        case request.request_method
        when "GET" then read_item(dataset, id, response)
        when "PUT" then replace_item(dataset, id, request, response)
        when "DELETE" then delete_item(dataset, id, response)
        else respond_method_not_allowed(response, allow: "GET, PUT, DELETE")
        end
      end

      def append_item(dataset, request, response)
        return unless writable?(dataset, response)

        item = parse_body(request, response)
        return if item.nil?

        id = @mount.overlay.append_item(dataset, item)
        response["Location"] = "#{request.path}/#{id}"
        respond_json(response, 201, item)
      rescue Overlay::Error => e
        respond_overlay_error(response, e)
      end

      def read_item(dataset, id, response)
        respond_json(response, 200, @mount.overlay.item(dataset, id))
      rescue Overlay::ItemNotFoundError
        respond_not_found(response)
      end

      def replace_item(dataset, id, request, response)
        return unless writable?(dataset, response)

        item = parse_body(request, response)
        return if item.nil?

        @mount.overlay.replace_item(dataset, id, item)
        respond_json(response, 200, item)
      rescue Overlay::ItemNotFoundError
        respond_not_found(response)
      rescue Overlay::Error => e
        respond_overlay_error(response, e)
      end

      def delete_item(dataset, id, response)
        return unless writable?(dataset, response)

        @mount.overlay.delete_item(dataset, id)
        response.status = 204
      rescue Overlay::ItemNotFoundError
        respond_not_found(response)
      end

      # Write guard: 403 for a read-only mount. SQLite datasets are
      # served via the copy-on-write overlay (ARCHITECTURE.md section 5a).
      def writable?(_dataset, response)
        unless @mount.writable?
          respond_error(response, 403, "package #{@mount.package.name} is read-only")
          return false
        end
        true
      end

      # The JSON request body, or nil after answering 400 (invalid JSON)
      # or 422 (a null body cannot be an item).
      def parse_body(request, response)
        body = JSON.parse(request.body.to_s)
        if body.nil?
          respond_error(response, 422, "request body must not be null")
          return nil
        end

        body
      rescue JSON::ParserError => e
        respond_error(response, 400, "invalid JSON body: #{e.message}")
        nil
      end

      def respond_overlay_error(response, error)
        case error
        when Overlay::ConflictError then respond_error(response, 409, error.message)
        when Overlay::SchemaViolationError
          respond_error(response, 422, "schema validation failed",
                        messages: error.messages)
        else respond_error(response, 422, error.message)
        end
      end
    end
  end
end
