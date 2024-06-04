# frozen_string_literal: true

# lib/capsium/package/metadata.rb
require "shale"
require "forwardable"

module Capsium
  class Package
    class Dependency < Shale::Mapper
      attribute :name, Shale::Type::String
      attribute :version, Shale::Type::String
    end

    class MetadataData < Shale::Mapper
      attribute :name, Shale::Type::String
      attribute :version, Shale::Type::String
      attribute :dependencies, Dependency, collection: true
    end

    class Metadata
      attr_reader :path, :data

      extend Forwardable
      def_delegator :@data, :name
      def_delegator :@data, :version
      def_delegator :@data, :dependencies

      def initialize(path)
        @path = path
        @data = if File.exist?(path)
                  MetadataData.from_json(File.read(path))
                else
                  MetadataData.new
                end
      end

      def to_json(*_args)
        @data.to_json
      end

      def save_to_file(output_path = @path)
        File.open(output_path, "w") do |file|
          file.write(to_json)
        end
      end
    end
  end
end
