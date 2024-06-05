# frozen_string_literal: true

# lib/capsium/package/routes.rb
require "json"
require "fileutils"

module Capsium
  class Package
    class RouteTarget < Shale::Mapper
      attribute :file, Shale::Type::String

      def fs_path(manifest)
        manifest.path_to_content_file(manifest.lookup(file).file)
      end

      def mime(manifest)
        manifest.lookup(file).mime
      end

      def validate(manifest)
        target_path = fs_path(manifest)
        return if File.exist?(target_path)

        raise "Route target does not exist: #{target_path}"
      end
    end

    class Route < Shale::Mapper
      attribute :path, Shale::Type::String
      attribute :target, RouteTarget
    end

    class RoutesData < Shale::Mapper
      attribute :routes, Route, collection: true

      def resolve(route)
        routes.detect do |r|
          r.path == route
        end
      end

      def add(route, target)
        target = RouteTarget.new(file: target) if target.is_a?(String)

        @routes << Route.new(path: route, target: target)
      end

      def update(route, updated_route, _updated_target)
        r = @routes.resolve(route)
        r.path = updated_route
        r.target = target
        r
      end

      def remove(route)
        r = @routes.resolve(route)
        @routes.remove(r)
      end

      def sort!
        @routes.sort_by!(&:path)
        self
      end
    end

    class Routes
      attr_reader :path, :data, :index, :manifest

      ROUTES_FILE = "routes.json"
      DEFAULT_INDEX_TARGET = "index.html"
      INDEX_ROUTE = "/"

      def initialize(path, manifest)
        @path = path
        @dir = File.dirname(path)
        @manifest = manifest
        @data = if File.exist?(path)
                  RoutesData.from_json(File.read(path))
                else
                  generate_routes_from_manifest
                end
        validate_index_path(@data.resolve(INDEX_ROUTE).target.file)
        validate
      end

      def resolve(url_path)
        @data.resolve(url_path)
      end

      def add_route(route, target)
        validate_route_target(route, target)
        @data.add(route, target)
      end

      def update_route(route, updated_route, updated_target)
        validate_route_target(updated_route, updated_target)
        @data.update(route, updated_route, updated_target)
      end

      def remove_route(route)
        @data._removed(route)
      end

      def validate
        @data.routes.each do |route|
          route.target.validate(@manifest)
        end
      end

      def to_json(*_args)
        @data.sort!.to_json
      end

      def save_to_file(output_path = @path)
        File.open(output_path, "w") do |file|
          file.write(to_json)
        end
      end

      private

      def generate_routes_from_manifest
        routes = RoutesData.new
        @manifest.data.content.each do |data_item|
          file_path = data_item.file
          content_path = @manifest.path_to_content_file(file_path).to_s

          if file_path == DEFAULT_INDEX_TARGET
            routes.add(INDEX_ROUTE, DEFAULT_INDEX_TARGET)
          end

          routes.add("/#{clean_target_html_path(file_path)}", file_path) if file_path =~ /\.html$/

          routes.add("/#{file_path}", file_path)
        end

        routes
      end

      def clean_target_html_path(path)
        File.dirname(path) != "." ?
          File.dirname(path) + File.basename(path, ".html") :
          File.basename(path, ".html")
      end

      def validate_index_path(index_path)
        target_path = @manifest.path_to_content_file(index_path)

        raise "Index file does not exist: #{target_path}" unless File.exist?(target_path)

        return if File.extname(target_path).downcase == ".html"

        raise "Index file is not an HTML file: #{target_path}"
      end
    end
  end
end
