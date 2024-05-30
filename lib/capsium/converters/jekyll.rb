# frozen_string_literal: true

# lib/capsium/converters/jekyll_to_capsium.rb
require "fileutils"
require "json"
require "capsium/packager"

module Capsium
  module Converters
    class Jekyll
      def initialize(site_directory, output_directory)
        @site_directory = site_directory
        @output_directory = output_directory
      end

      def convert
        validate_site_directory
        package_directory = prepare_package_directory
        packager = Capsium::Packager.new(package_directory)
        packager.pack
        cleanup_package_directory(package_directory)
      end

      private

      def validate_site_directory
        return if Dir.exist?(@site_directory) && File.exist?(File.join(@site_directory, "index.html"))

        raise "Invalid Jekyll site directory: #{@site_directory}"
      end

      def prepare_package_directory
        package_directory = File.join(@output_directory, "capsium_package")
        FileUtils.mkdir_p(package_directory)

        FileUtils.cp_r(Dir.glob("#{@site_directory}/*"), package_directory)

        create_manifest(package_directory)

        package_directory
      end

      def create_manifest(package_directory)
        manifest = {
          "name" => "jekyll_site",
          "version" => "1.0.0",
          "description" => "A Jekyll site converted to a Capsium package",
          "files" => Dir.glob("#{package_directory}/**/*").map { |file| file.sub("#{package_directory}/", "") }
        }

        File.write(File.join(package_directory, "manifest.json"), JSON.pretty_generate(manifest))
      end

      def cleanup_package_directory(package_directory)
        FileUtils.rm_rf(package_directory)
      end
    end
  end
end
