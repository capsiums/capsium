# frozen_string_literal: true

require "forwardable"

module Capsium
  class Package
    class Routes
      extend Forwardable

      attr_reader :path, :config, :manifest, :storage

      def_delegators :@config, :to_hash

      INDEX_ROUTE = "/"
      INDEX_RESOURCE = "content/index.html"
      DATASET_ROUTE_PREFIX = "/api/v1/data/"

      def initialize(path, manifest, storage)
        @path = path
        @manifest = manifest
        @storage = storage
        @config = if File.exist?(path)
                    RoutesConfig.from_json(File.read(path))
                  else
                    generate_routes
                  end
      end

      def resolve(url_path)
        @config.resolve(url_path)
      end

      def add_route(route, target)
        @config.add(route, target)
      end

      def update_route(route, updated_route, updated_target)
        @config.update(route, updated_route, updated_target)
      end

      def remove_route(route)
        @config.remove(route)
      end

      def to_json(*_args)
        @config.to_json
      end

      def save_to_file(output_path = @path)
        File.write(output_path, to_json)
      end

      # Auto-generation (ARCHITECTURE.md section 4): every manifest
      # resource gets a route at its path relative to content/; HTML files
      # get two routes (basename without extension and full filename); the
      # index HTML additionally gets "/"; every dataset in storage gets
      # /api/v1/data/<id>. Output is deterministic (sorted by path).
      def generate_routes
        routes = resource_routes + dataset_routes
        RoutesConfig.new(index: index_resource, routes: routes.sort_by(&:path))
      end

      private

      def index_resource
        INDEX_RESOURCE if @manifest.resources.key?(INDEX_RESOURCE)
      end

      def resource_routes
        @manifest.resources.keys.flat_map do |resource_path|
          routes_for_resource(resource_path)
        end.uniq(&:path)
      end

      def routes_for_resource(resource_path)
        url_path = resource_path.sub(%r{\A#{Package::CONTENT_DIR}/}o, "")
        routes = [Route.new(path: "/#{url_path}", resource: resource_path)]
        return routes unless File.extname(resource_path) == ".html"

        basename = File.basename(url_path, ".html")
        routes << Route.new(path: "/#{basename}", resource: resource_path)
        routes << Route.new(path: INDEX_ROUTE, resource: resource_path) if index?(resource_path)
        routes
      end

      def index?(resource_path)
        resource_path == INDEX_RESOURCE
      end

      def dataset_routes
        @storage.dataset_names.map do |name|
          Route.new(path: "#{DATASET_ROUTE_PREFIX}#{name}", dataset: name)
        end
      end
    end
  end
end
