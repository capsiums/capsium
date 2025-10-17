# frozen_string_literal: true

# lib/capsium/package/metadata.rb
require "forwardable"
require_relative "metadata_config"

module Capsium
  class Package
    class Metadata
      attr_reader :path, :config

      extend Forwardable
      def_delegator :@config, :to_json
      def_delegator :@config, :identifier
      def_delegator :@config, :uuid
      def_delegator :@config, :name
      def_delegator :@config, :version
      def_delegator :@config, :description
      def_delegator :@config, :author
      def_delegator :@config, :license
      def_delegator :@config, :repository
      def_delegator :@config, :access_mode
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
        File.write(output_path, to_json)
      end
    end
  end
end
