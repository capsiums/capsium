# frozen_string_literal: true

require "fileutils"
require "find"
require "json"
require "pathname"
require "securerandom"

module Capsium
  module Converters
    # Shared base for "static-site-generator output → Capsium package"
    # converters. Each SSG (Astro, Hugo, Next, plain static) produces a
    # directory of HTML/CSS/JS/image assets with a per-SSG URL
    # convention; this base walks the tree, infers routes, and lays
    # out a Capsium package directory the user can then `capsium
    # package pack`.
    #
    # Subclasses set ASSET_DIRECTORIES (relative to source root) and
    # optionally override infer_route_for to handle quirks (Astro's
    # _astro/ bundle dir, Next's trailing-slash config, Hugo's
    # section index files).
    class StaticSite
      Result = Data.define(:source, :output, :routes_added, :assets_copied)

      attr_reader :source_dir, :output_dir, :package_name, :exclude

      # @param source_dir [String] the SSG's built output directory
      #   (Astro dist/, Hugo public/, Next out/)
      # @param output_dir [String] the Capsium package directory to
      #   create. Defaults to ./<source basename>-package.
      # @param package_name [String, nil] the Capsium metadata.name.
      #   Defaults to the source directory's basename.
      # @param exclude [Array<String>] extra path globs to skip beyond
      #   the SSG's own build artifacts.
      def initialize(source_dir:, output_dir: nil, package_name: nil, exclude: [])
        @source_dir = File.expand_path(source_dir)
        @output_dir = File.expand_path(output_dir || default_output_dir,
                                       File.dirname(@source_dir))
        @package_name = package_name || File.basename(@source_dir)
        @exclude = exclude
      end

      def convert
        prepare_output
        routes = copy_assets_and_infer_routes
        write_metadata
        write_routes(routes)
        Result.new(source: source_dir, output: output_dir,
                   routes_added: routes.size, assets_copied: count_copied_assets)
      end

      # Hook for SSG-specific exclusions: Astro's _astro/, Hugo's
      # index.xml RSS, Next's __next__, etc. Returns an array of
      # basename prefixes/directories to skip during route inference.
      def asset_exclusions
        []
      end

      private

      def default_output_dir
        "#{File.basename(@source_dir)}-capsium"
      end

      def prepare_output
        FileUtils.mkdir_p(output_dir)
        FileUtils.mkdir_p(File.join(output_dir, "content"))
      end

      # Walks source_dir recursively. For every file not in an
      # excluded location, copies to <output>/content/<relative-path>
      # and infers the serving route(s). Returns an array of
      # { path:, resource: } entries for routes.json.
      def copy_assets_and_infer_routes
        routes = []
        each_source_file do |absolute|
          relative = Pathname.new(absolute).relative_path_from(Pathname.new(source_dir)).to_s
          next if excluded?(relative)

          copy_to_content(relative, absolute)
          routes.concat(infer_routes_for(relative))
        end
        routes.uniq { |r| r[:path] }.sort_by { |r| r[:path] }
      end

      def each_source_file
        Find.find(source_dir) do |path|
          next if File.directory?(path)

          yield path
        end
      end

      def excluded?(relative)
        segments = relative.split("/")
        return true if segments.intersect?(asset_exclusions)

        @exclude.any? { |glob| File.fnmatch(glob, relative) }
      end

      def copy_to_content(relative, absolute)
        target = File.join(output_dir, "content", relative)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(absolute, target)
      end

      # Route inference (ARCHITECTURE.md §4):
      #   index.html at folder root → that folder's path
      #   <name>.html → /<name> AND /<name>.html (basename + filename)
      #   everything else → /<relative-path>
      # The root index.html additionally gets "/".
      def infer_routes_for(relative)
        resource = "content/#{relative}"
        routes = []

        if relative == "index.html"
          routes << { path: "/", resource: resource }
          routes << { path: "/index.html", resource: resource }
          routes << { path: "/index", resource: resource }
          return routes
        end

        if relative.end_with?("/index.html")
          folder = relative.delete_suffix("/index.html")
          routes << { path: "/#{folder}", resource: resource }
          routes << { path: "/#{folder}/", resource: resource }
          routes << { path: "/#{folder}/index.html", resource: resource }
          return routes
        end

        if File.extname(relative) == ".html"
          basename = relative.delete_suffix(".html")
          routes << { path: "/#{basename}", resource: resource }
          routes << { path: "/#{relative}", resource: resource }
          return routes
        end

        routes << { path: "/#{relative}", resource: resource }
      end

      def write_metadata
        File.write(File.join(output_dir, "metadata.json"),
                   JSON.pretty_generate(metadata_payload))
      end

      def metadata_payload
        uuid = SecureRandom.uuid
        {
          name: package_name,
          version: "0.1.0",
          guid: "urn:uuid:#{uuid}",
          uuid: uuid,
          description: "Converted from #{self.class.name.split('::').last} static output."
        }
      end

      def write_routes(routes)
        File.write(File.join(output_dir, "routes.json"),
                   JSON.pretty_generate(routes_payload(routes)))
      end

      def routes_payload(routes)
        {
          index: "content/index.html",
          routes: routes.map { |r| { path: r[:path], resource: r[:resource] } }
        }
      end

      def count_copied_assets
        Dir.glob(File.join(output_dir, "content", "**", "*")).count { |p| File.file?(p) }
      end
    end
  end
end
