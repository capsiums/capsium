# frozen_string_literal: true

# lib/capsium/package/manifest.rb
require "json"
require "marcel"
require "shale"
require_relative "manifest_config"

module Capsium
  class Package
    class Manifest
      extend Forwardable
      attr_accessor :path, :content_path, :config

      def_delegators :@config, :to_json

      def initialize(path)
        @path = path
        @content_path = File.join(File.dirname(@path), Package::CONTENT_DIR)

        @config = if File.exist?(path)
            ManifestConfig.from_json(File.read(path))
          else
            ManifestConfig.new(content: generate_manifest)
          end
      end

      def generate_manifest
        files = Dir[File.join(@content_path, "**", "*")].reject do |f|
          File.directory?(f)
        end

        files.sort.map do |file_path|
          ManifestConfigItem.new(
            file: relative_path(file_path),
            mime: mime_from_path(file_path),
          )
        end
      end

      def lookup(filename)
        @config.content.detect do |data_item|
          data_item.file == filename
        end
      end

      def save_to_file(output_path = @path)
        @config.content.sort_by!(&:file)
        File.open(output_path, "w") do |file|
          file.write(to_json)
        end
      end

      def path_to_content_file(path)
        raise TypeError, "Path cannot be nil" if path.nil?

        Pathname.new(File.dirname(@path)).join(path)
      end

      def content_file_exists?(path)
        File.exist?(path_to_content_file(path))
      end

      def relative_path(path)
        Pathname.new(path).relative_path_from(File.dirname(@path)).to_s
      end

      private

      def mime_from_path(path)
        Marcel::MimeType.for(
          Pathname.new(path),
          name: File.basename(path),
          extension: File.extname(path),
        )
      end
    end
  end
end
