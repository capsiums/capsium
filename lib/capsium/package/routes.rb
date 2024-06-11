# frozen_string_literal: true

# lib/capsium/package/routes.rb
require "json"
require "fileutils"
require_relative "routes_config"

module Capsium
  class Package
    class Routes
      extend Forwardable
      attr_reader :config

      def_delegators :@config, :to_json

      attr_reader :path, :config, :index, :manifest, :storage

      ROUTES_FILE = "routes.json"
      DEFAULT_INDEX_TARGET = "content/index.html"
      INDEX_ROUTE = "/"

      def initialize(path, manifest, storage)
        @path = path
        @dir = File.dirname(path)
        @manifest = manifest
        @storage = storage
        @config = if File.exist?(path)
            RoutesConfig.from_json(File.read(path))
          else
            generate_routes_from_manifest
          end
        validate_index_path(@config.resolve(INDEX_ROUTE)&.target&.file)
        validate
      end

      def resolve(url_path)
        @config.resolve(url_path)
      end

      def add_route(route, target)
        validate_route_target(route, target)
        @config.add(route, target)
      end

      def update_route(route, updated_route, updated_target)
        validate_route_target(updated_route, updated_target)
        @config.update(route, updated_route, updated_target)
      end

      def remove_route(route)
        @config.remove(route)
      end

      def validate
        @config.routes.each { |route| route.target.validate(@manifest, @storage) }
      end

      def to_json(*_args)
        @config.sort!.to_json
      end

      def save_to_file(output_path = @path)
        File.open(output_path, "w") { |file| file.write(to_json) }
      end

      private

      def generate_routes_from_manifest
        routes = RoutesConfig.new
        @manifest.config.content.each do |data_item|
          file_path = data_item.file

          if file_path == DEFAULT_INDEX_TARGET
            routes.add(INDEX_ROUTE, DEFAULT_INDEX_TARGET)
          end

          routes.add("/#{clean_target_html_path(file_path)}", file_path) if file_path =~ /\.html$/
          routes.add("/#{file_path}", file_path)
        end
        routes
      end

      def clean_target_html_path(path)
        File.dirname(path) != "." ? File.dirname(path) + File.basename(path, ".html") : File.basename(path, ".html")
      end

      def validate_index_path(index_path)
        return unless index_path

        target_path = @manifest.path_to_content_file(index_path)
        raise "Index file does not exist: #{target_path}" unless File.exist?(target_path)
        raise "Index file is not an HTML file: #{target_path}" unless File.extname(target_path).downcase == ".html"
      end
    end
  end
end
