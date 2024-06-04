# frozen_string_literal: true

# lib/capsium/package/routes.rb
require "json"
require "fileutils"

module Capsium
  class Package
    class RouteTarget < Shale::Mapper
      attribute :file, Shale::Type::String

      def validate(manifest)
        return if manifest.content_file_exists?(file)

        raise "Route target does not exist: #{file}"
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
      DEFAULT_INDEX_TARGET = "/index.html"
      INDEX_ROUTE = "/"

      def initialize(path, manifest)
        @path = path
        @dir = File.dirname(path)
        @manifest = manifest
        ensure_default_index_path
        @data = if File.exist?(path)
                  RoutesData.from_json(File.read(path))
                else
                  generate_routes_from_manifest
                end
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
          route.target.validate
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

      def ensure_default_index_path
        @index ||= DEFAULT_INDEX_TARGET
        validate_index_path(@index)
      end

      def generate_routes_from_manifest
        routes = RoutesData.new
        @manifest.data.content.each do |data_item|
          file_path = data_item.file
          # mime_type = data_item.mime

          routes.add(INDEX_ROUTE, file_path) if file_path == "index.html"

          routes.add("/#{clean_target_html_path(file_path)}", file_path) if file_path =~ /\.html$/

          routes.add("/#{file_path}", file_path)
        end

        routes
      end

      def clean_target_html_path(path)
        File.dirname(path)[1..] + File.basename(path, ".html")
      end

      def validate_route_target(route)
        routes.resolve @manifest.path_to_file(index)

        target_path = File.join(@dir, route[:path])
        return if File.exist?(target_path)

        raise "Target file does not exist: #{route[:path]}"
      end

      def validate_index_path(index_path)
        target_path = @manifest.path_to_content_file(index_path)
        exists = @manifest.content_file_exists?(
          index_path[0] == "/" ? index_path[1..] : index_path
        )

        raise "Index file does not exist: #{index_path} => #{target_path}" unless exists

        return if File.extname(target_path).downcase == ".html"

        raise "Index file is not an HTML file: #{index_path} => #{target_path}"
      end
    end
  end
end
