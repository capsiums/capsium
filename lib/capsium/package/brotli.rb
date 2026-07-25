# frozen_string_literal: true

require "brotli"
require "fileutils"

module Capsium
  class Package
    # Generates Brotli-precompressed sidecars for text resources so a
    # reactor can serve `.br` to capable clients with zero runtime
    # cost. Sidecars live alongside their originals:
    #
    #   content/index.html  →  content/index.html.br
    #
    # The manifest is NOT extended — the reactor discovers sidecars by
    # probing for `<path>.br` at serve time and gates on
    # `Accept-Encoding: br`. Keeping the manifest unchanged means
    # legacy reactors ignore the sidecars; new reactors pick them up
    # automatically.
    #
    # Compression is restricted to text-like MIME types (no images,
    # fonts, already-compressed formats); the list is conservative on
    # purpose — extending it is a one-line change.
    class Brotli
      COMPRESSIBLE_EXTENSIONS = %w[
        .html .htm .css .js .mjs .json .yaml .yml .svg .xml .txt .csv
        .tsv .md .adoc .rst .webmanifest
      ].freeze

      SIDECAR_SUFFIX = ".br"

      attr_reader :package

      def initialize(package)
        @package = package
      end

      # Writes a <file>.br sidecar next to every compressible resource
      # AND registers each sidecar in the manifest so the integrity
      # check covers it. Returns the list of generated sidecar paths
      # (relative to the package directory). Existing sidecars are
      # overwritten; manifest entries are refreshed so a stale sidecar
      # entry pointing at a now-removed source is replaced, not
      # duplicated.
      def generate
        compressible_files.filter_map do |relative_path|
          sidecar = write_sidecar(relative_path)
          next nil unless sidecar

          package.manifest.add_resource(sidecar, type: "application/brotli")
          sidecar
        end
      end

      class << self
        # Convenience: generate brotli sidecars for a package in one
        # call. Returns the list of generated sidecar paths.
        def generate(package)
          new(package).generate
        end

        def compressible?(relative_path)
          COMPRESSIBLE_EXTENSIONS.include?(File.extname(relative_path).downcase)
        end
      end

      private

      def compressible_files
        package.manifest.resources.keys.select do |path|
          self.class.compressible?(path)
        end
      end

      def write_sidecar(relative_path)
        source = File.join(package.path, relative_path)
        return nil unless File.file?(source)

        target = File.join(package.path, "#{relative_path}#{SIDECAR_SUFFIX}")
        FileUtils.mkdir_p(File.dirname(target))
        # ::Brotli is the top-level brotli gem; this class is also
        # named Brotli so the unqualified name would resolve to self.
        File.binwrite(target, ::Brotli.deflate(File.read(source), quality: 11))
        "#{relative_path}#{SIDECAR_SUFFIX}"
      end
    end
  end
end
