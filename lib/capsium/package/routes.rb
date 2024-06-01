# frozen_string_literal: true

# lib/capsium/package/routes.rb
require "json"
require "fileutils"

module Capsium
  class Package
    class Routes
      attr_reader :path, :routes, :index, :manifest

      ROUTES_FILE = "routes.json"
      DEFAULT_INDEX_TARGET = "/index.html"
      INDEX_ROUTE = "/"

      def initialize(path, manifest)
        @path = path
        @dir = File.dirname(path)
        @manifest = manifest
        ensure_default_index_path
        @routes = load_routes || generate_routes_from_manifest
      end

      def add_route(route)
        validate_route_target(route)
        @routes ||= {}
        @routes[route[:url]] = route[:path]
        save_routes
      end

      def update_route(index, updated_route)
        validate_route_target(updated_route)
        route_key = @routes.keys[index]
        @routes[route_key] = updated_route[:path]
        save_routes
      end

      def remove_route(index)
        route_key = @routes.keys[index]
        @routes.delete(route_key)
        save_routes
      end

      def get_routes
        @routes || {}
      end

      def as_json
        { routes: routes }
      end

      def to_json(*_args)
        JSON.pretty_generate(as_json)
      end

      def save_to_file(output_path = @path)
        File.open(output_path, "w") do |file|
          file.write(to_json)
        end
      end

      private

      def load_routes
        return unless File.exist?(@path)

        hash = JSON.parse(File.read(@path))
        hash["routes"] or return
      end

      def ensure_default_index_path
        @index ||= DEFAULT_INDEX_TARGET
        validate_index_path
      end

      def generate_routes_from_manifest
        routes = {}
        @manifest.data.content.each do |data_item|
          file_path = data_item.file
          mime_type = data_item.mime

          routes[INDEX_ROUTE] = file_path if file_path == "index.html"

          routes["/#{clean_html_path(file_path)}"] = file_path if file_path =~ /\.html$/

          routes["/#{file_path}"] = file_path
        end

        routes
      end

      def clean_html_path(path)
        File.dirname(path)[1..] + File.basename(path, ".html")
      end

      def validate_route_target(route)
        target_path = File.join(@dir, route[:path])
        return if File.exist?(target_path)

        raise "Target file does not exist: #{route[:path]}"
      end

      def validate_index_path
        target_path = File.join(@dir, "content", index)
        raise "Index file does not exist: #{index}" unless File.exist?(target_path)
        return if File.extname(target_path).downcase == ".html"

        raise "Index file is not an HTML file: #{index}"
      end
    end
  end
end
