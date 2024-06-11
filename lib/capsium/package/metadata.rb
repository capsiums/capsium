# frozen_string_literal: true

# lib/capsium/package/metadata.rb
require "shale"
require "forwardable"
require_relative "metadata_config"

module Capsium
  class Package
    class Metadata
      attr_reader :path, :config

      extend Forwardable
      def_delegator :@config, :to_json
      def_delegator :@config, :name
      def_delegator :@config, :version
      def_delegator :@config, :description # Delegate description method
      def_delegator :@config, :dependencies

      def initialize(path)
        @path = path
        @config = if File.exist?(path)
            MetadataData.from_json(File.read(path))
          else
            MetadataData.new
          end
      end

      def save_to_file(output_path = @path)
        File.open(output_path, "w") do |file|
          file.write(to_json)
        end
      end
    end
  end
end
