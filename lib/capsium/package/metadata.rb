# frozen_string_literal: true

# lib/capsium/package/metadata.rb
require "json"

module Capsium
  class Package
    class Metadata
      attr_reader :name, :version, :dependencies

      def initialize(path)
        @path = path
        @dir = File.dirname(path)
        load_metadata
      end

      def load_metadata
        return unless File.exist?(@path)

        metadata_data = JSON.parse(File.read(@path))
        @name = metadata_data["name"]
        @version = metadata_data["version"]
        @dependencies = metadata_data["dependencies"] || {}
      end

      def as_json
        {
          name: @name,
          version: @version,
          dependencies: @dependencies
        }
      end

      def to_json(*_args)
        JSON.pretty_generate(as_json)
      end

      def save_to_file(output_path = @path)
        File.open(output_path, "w") do |file|
          file.write(to_json)
        end
      end
    end
  end
end
