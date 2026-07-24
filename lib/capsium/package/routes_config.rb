# frozen_string_literal: true

require "json"
require "lutaml/model"

module Capsium
  class Package
    # The "responseRewrite" object of an inherited route (05x-routing
    # section "Route Inheritance"): replaces the served body and/or
    # overrides response headers.
    class ResponseRewrite < Lutaml::Model::Serializable
      attribute :body, :string
      attribute :headers, :hash

      json do
        map :body, to: :body
        map :headers, to: :headers
      end
    end

    # A single route entry (ARCHITECTURE.md section 4). Kinds are
    # discriminated by key, MECE:
    # - {path, resource, headers?, visibility?} -- static file
    # - {path, dataset, accessControl?}        -- dataset route
    # - {path, method, handler, ...}           -- dynamic handler (parsed,
    #   accepted-and-ignored; reactors respond 501)
    #
    # Route inheritance (05x-routing): a resource of the form
    # "<dependency-guid>/<path>" (a URI, i.e. containing "://") pulls
    # content from a dependency package; "remap" replaces the serving
    # path; "responseRewrite"/"responseHeaders" post-process the
    # response; "requestHeaders" are recorded for forwarding reactors
    # (the Ruby reactor serves statically and does not forward, so they
    # do not alter its responses).
    class Route < Lutaml::Model::Serializable
      DATASET_PATH_PREFIX = "/api/v1/data/"

      attribute :path, :string
      attribute :resource, :string
      attribute :headers, :hash
      attribute :headers_file, :string
      attribute :visibility, :string, values: Resource::VISIBILITIES
      attribute :dataset, :string
      attribute :access_control, :hash
      attribute :http_method, :string
      attribute :handler, :string
      attribute :remap, :string
      attribute :response_rewrite, ResponseRewrite
      attribute :response_headers, :hash
      attribute :request_headers, :hash

      json do
        map :path, to: :path
        map :resource, to: :resource
        map :headers, to: :headers
        map "headersFile", to: :headers_file
        map :visibility, to: :visibility
        map :dataset, to: :dataset
        map "accessControl", to: :access_control
        map "method", to: :http_method
        map :handler, to: :handler
        map :remap, to: :remap
        map "responseRewrite", to: :response_rewrite
        map "responseHeaders", to: :response_headers
        map "requestHeaders", to: :request_headers
      end

      def kind
        return :resource if resource
        return :dataset if dataset

        :handler
      end

      def dataset_route?
        kind == :dataset
      end

      def handler_route?
        kind == :handler
      end

      # The URL path this route answers at: the remapped path when the
      # route remaps an inherited route, its own path otherwise.
      def serving_path
        remap || path
      end

      # Whether the resource addresses content of a dependency package
      # ("<dependency-guid>/<path>" — a URI rather than a
      # package-relative path).
      def dependency_reference?
        resource.is_a?(String) && resource.include?("://")
      end

      # Whether the route carries route-inheritance attributes.
      def inherited?
        dependency_reference? || !remap.nil? || !response_rewrite.nil? ||
          !response_headers.nil? || !request_headers.nil?
      end

      def fs_path(package_path)
        return unless resource

        File.join(package_path, resource)
      end

      def mime(manifest)
        manifest.type_for(resource)
      end

      def validate_target(package_path, storage, merged_view: nil)
        return if handler_route?
        return if dependency_reference?

        if dataset_route?
          return if storage.dataset(dataset)

          raise Error, "Route dataset does not exist: #{dataset}"
        end
        validate_resource_target(package_path, merged_view)
      end

      private

      def validate_resource_target(package_path, merged_view)
        found = if merged_view
                  merged_view.resolve(resource)
                else
                  target_path = fs_path(package_path)
                  target_path && File.exist?(target_path)
                end
        return if found

        raise Error, "Route resource does not exist: #{resource}"
      end
    end

    # Canonical routes.json model: optional top-level "index" plus a
    # "routes" array. The legacy gem form ({path, target: {file|dataset}})
    # is accepted on read and normalized; writers emit only the canonical
    # form.
    class RoutesConfig < Lutaml::Model::Serializable
      attribute :index, :string
      attribute :routes, Route, collection: true, default: []

      json do
        map :index, to: :index
        map :routes, with: { from: :routes_from_json, to: :routes_to_json }
      end

      def self.from_json(json)
        doc = JSON.parse(json)
        doc["routes"] = normalize_routes(doc["routes"])
        super(JSON.generate(doc))
      end

      # Routes may arrive in three read-tolerated shapes; writers emit
      # only the canonical array of {path, kind, ...}:
      #   - Array  — canonical form (CC 62001 §05x-routing).
      #   - Hash   — Annex E object-keyed-by-path legacy form
      #              ({"/x": {...}}); expanded to the array form with
      #              the key merged in as "path".
      #   - nil    — treated as an empty routes array.
      def self.normalize_routes(value)
        case value
        when nil then []
        when Array then value.map { |route| normalize_route(route) }
        when Hash then normalize_object_form(value)
        else
          raise Error, "Invalid routes.json: \"routes\" must be an array " \
                       "or object, got #{value.class}"
        end
      end

      # Expands the Annex E object-keyed form into the canonical array
      # form. Each `{ path => body }` becomes `{ "path" => path, **body }`.
      # A "path" key inside the body is rejected — the outer key wins and
      # a conflicting inner value indicates user confusion worth surfacing.
      def self.normalize_object_form(object)
        object.map do |path, body|
          body = {} unless body.is_a?(Hash)
          if body.key?("path") && body["path"] != path
            raise Error, "Invalid routes.json: object-keyed entry #{path.inspect} " \
                         "conflicts with inner \"path\": #{body['path'].inspect}"
          end

          normalize_route(body.merge("path" => path))
        end
      end
      private_class_method :normalize_routes, :normalize_object_form

      def self.normalize_route(route)
        target = route.delete("target")
        return route unless target.is_a?(Hash)

        route.merge("resource" => target["file"], "dataset" => target["dataset"]).compact
      end
      private_class_method :normalize_route

      def routes_from_json(model, value)
        model.routes = (value || []).map { |route| Route.from_json(JSON.generate(route)) }
      end

      # Writers emit the canonical form only: deterministic, sorted by path.
      def routes_to_json(model, doc)
        doc["routes"] = model.routes.sort_by(&:path).map do |route|
          JSON.parse(route.to_json)
        end
      end

      def resolve(path)
        routes.detect { |route| route.serving_path == path }
      end

      def add(path, target)
        route = Route.new(path: path, resource: target)
        self.routes = routes + [route]
        route
      end

      def update(path, updated_path, updated_target)
        route = resolve(path)
        route.path = updated_path
        route.resource = updated_target
        route
      end

      def remove(path)
        self.routes = routes.reject { |route| route.path == path }
      end

      def sort!
        self.routes = routes.sort_by(&:path)
        self
      end
    end
  end
end
