# frozen_string_literal: true

# lib/capsium/package/manifest.rb
require "json"
require "mime/types"

module Capsium
  class Package
    class Manifest
      attr_reader :content

      def initialize(path)
        @path = path
        @content_path = File.join(File.dirname(path), "content")
        @content = load_manifest || generate_manifest
      end

      def load_manifest
        return unless File.exist?(@path)

        manifest_data = JSON.parse(File.read(@path))
        manifest_data["content"]
      end

      def generate_manifest
        files = Dir[File.join(@content_path, "**", "*")].reject { |f| File.directory?(f) }

        @content = files.each_with_object({}) do |file, hash|
          relative_path = Pathname.new(file).relative_path_from(@content_path).to_s
          mime_type = MIME::Types.type_for(file).first.content_type
          hash[relative_path] = mime_type
        end
      end

      def as_json
        { content: content }
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
