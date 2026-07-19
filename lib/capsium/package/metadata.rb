# frozen_string_literal: true

require "forwardable"

module Capsium
  class Package
    class Metadata
      attr_reader :path, :config

      extend Forwardable

      def_delegators :@config, :to_json, :to_hash, :name, :version,
                     :description, :guid, :uuid, :author, :license,
                     :repository, :dependencies

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
