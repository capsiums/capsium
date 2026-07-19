# frozen_string_literal: true

require "forwardable"
require "marcel"
require "pathname"

module Capsium
  class Package
    class Manifest
      extend Forwardable

      attr_reader :path, :content_path, :config

      def_delegators :@config, :to_hash

      def initialize(path)
        @path = path
        @content_path = File.join(File.dirname(@path), Package::CONTENT_DIR)
        @config = if File.exist?(path)
                    ManifestConfig.from_json(File.read(path))
                  else
                    ManifestConfig.new(resources: generate_manifest)
                  end
      end

      # Auto-generation (ARCHITECTURE.md section 3): scan content/
      # recursively, detect MIME types, default visibility "exported",
      # deterministic (sorted) output.
      def generate_manifest
        content_files.sort.to_h do |file_path|
          [relative_path(file_path),
           Resource.new(type: mime_from_path(file_path), visibility: "exported")]
        end
      end

      def resources
        @config.resources
      end

      def lookup(path)
        resources[path]
      end

      def type_for(path)
        resource = lookup(path)
        resource&.type
      end

      def to_json(*_args)
        @config.to_json
      end

      def save_to_file(output_path = @path)
        File.write(output_path, to_json)
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

      def content_files
        Dir.glob(File.join(@content_path, "**", "*"), File::FNM_DOTMATCH).select do |file|
          File.file?(file)
        end
      end

      def mime_from_path(path)
        Marcel::MimeType.for(
          Pathname.new(path),
          name: File.basename(path),
          extension: File.extname(path)
        )
      end
    end
  end
end
