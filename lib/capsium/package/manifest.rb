# frozen_string_literal: true

# lib/capsium/package/manifest.rb
require "json"
require "marcel"
require "shale"

module Capsium
  class Package
    class Manifest
      attr_accessor :path, :content_path, :data

      def initialize(path)
        @path = path
        # This is {package-name}/content
        # or
        # /tmp/../content
        @content_path = File.join(File.dirname(@path), "content")

        @data = if File.exist?(path)
                  ManifestData.from_json(File.read(path))
                else
                  ManifestData.new(content: generate_manifest)
                end
      end

      def generate_manifest
        files = Dir[File.join(@content_path, "**", "*")].reject do |f|
          File.directory?(f)
        end

        files.sort.map do |file_path|
          ManifestDataItem.new(
            file: relative_path(file_path),
            mime: mime_from_path(file_path)
          )
        end
      end

      def lookup(filename)
        @data.content.detect do |data_item|
          data_item.file == filename
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

      def path_to_content_file(path)
        Pathname.new(@content_path).join(path)
      end

      def content_file_exists?(path)
        File.exist?(path_to_content_file(path))
      end

      def relative_path(path)
        Pathname.new(path).relative_path_from(@content_path).to_s
      end

      private

      def mime_from_path(path)
        Marcel::MimeType.for(
          Pathname.new(path),
          name: File.basename(path),
          extension: File.extname(path)
        )
      end
    end

    class ManifestDataItem < Shale::Mapper
      attribute :file, Shale::Type::String
      attribute :mime, Shale::Type::String

      # json do
      #   map "file", to: :file
      #   map "mime", to: :mime
      # end
    end

    class ManifestData < Shale::Mapper
      attribute :content, ManifestDataItem, collection: true

      # json do
      #   map "content", to: :content
      # end
    end
  end
end
