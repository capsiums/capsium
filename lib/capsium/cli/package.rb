# frozen_string_literal: true

require "json"

module Capsium
  class Cli
    class Package < Thor
      extend ThorExt::Start

      desc "info PACKAGE_PATH", "Display information about the package"

      def info(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts "Package Path: #{package.path}"
        puts "Routes: #{package.routes.to_hash}"
        puts "Manifest: #{package.manifest.to_hash}"
      end

      desc "manifest PATH_TO_PACKAGE",
           "Show the manifest content of the package"

      def manifest(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.manifest.to_hash)
      end

      desc "storage PATH_TO_PACKAGE", "Show the storage datasets of the package"

      def storage(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.storage.to_hash)
      end

      desc "routes PATH_TO_PACKAGE", "Show the routes of the package"

      def routes(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.routes.to_hash)
      end

      desc "metadata PATH_TO_PACKAGE", "Show the metadata of the package"

      def metadata(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.metadata.to_hash)
      end

      desc "pack PATH_TO_PACKAGE_FOLDER", "Package the files into the package"
      option :force, type: :boolean, default: false, aliases: "-f"

      def pack(path_to_package)
        package = Capsium::Package.new(path_to_package)
        packager = Capsium::Packager.new
        packager.pack(package, options)
      rescue StandardError => e
        puts e
        puts e.inspect
        puts e.backtrace
      end
    end
  end
end
