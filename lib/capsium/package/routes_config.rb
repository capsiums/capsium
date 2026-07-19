# frozen_string_literal: true

require "json"
require "lutaml/model"

module Capsium
  class Package
    # A single route entry (ARCHITECTURE.md section 4). Kinds are
    # discriminated by key, MECE:
    # - {path, resource, headers?, visibility?} -- static file
    # - {path, dataset, accessControl?}        -- dataset route
    # - {path, method, handler, ...}           -- dynamic handler (parsed,
    #   accepted-and-ignored; reactors respond 501)
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

      def fs_path(package_path)
        return unless resource

        File.join(package_path, resource)
      end

      def mime(manifest)
        manifest.type_for(resource)
      end

      def validate_target(package_path, storage)
        return if handler_route?

        if dataset_route?
          return if storage.dataset(dataset)

          raise Error, "Route dataset does not exist: #{dataset}"
        end
        validate_resource_target(package_path)
      end

      private

      def validate_resource_target(package_path)
        target_path = fs_path(package_path)
        return if target_path && File.exist?(target_path)

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
        doc["routes"] = (doc["routes"] || []).map { |route| normalize_route(route) }
        super(JSON.generate(doc))
      end

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
        routes.detect { |route| route.path == path }
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
