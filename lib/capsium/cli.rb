# frozen_string_literal: true

# lib/capsium/cli.rb
require "thor"
require_relative "package"
require_relative "reactor"
require_relative "thor_ext"
require_relative "converters/jekyll"

module Capsium
  class Cli < Thor
    extend ThorExt::Start

    class Package < Thor
      extend ThorExt::Start

      desc "info PACKAGE_PATH", "Display information about the package"
      def info(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts "Package Path: #{package.path}"
        puts "Routes: #{package.routes.as_json}"
        puts "Manifest: #{package.manifest.as_json}"
      end

      desc "manifest PATH_TO_PACKAGE", "Show the manifest content of the package"
      def manifest(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.manifest.as_json)
      end

      desc "storage PATH_TO_PACKAGE", "Show the storage datasets of the package"
      def storage(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.storage.as_json)
      end

      desc "routes PATH_TO_PACKAGE", "Show the routes of the package"
      def routes(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.routes.as_json)
      end

      desc "metadata PATH_TO_PACKAGE", "Show the metadata of the package"
      def metadata(path_to_package)
        package = Capsium::Package.new(path_to_package)
        puts JSON.pretty_generate(package.metadata.as_json)
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

    class Reactor < Thor
      extend ThorExt::Start
      desc "serve PACKAGE_PATH", "Start the Capsium reactor to serve the package"
      def serve(path_to_package)
        package = Capsium::Package.new(path_to_package)
        reactor = Capsium::Reactor.new(package)
        reactor.serve
      rescue StandardError => e
        puts e
        puts e.inspect
        puts e.backtrace
      ensure
        package.cleanup
      end
    end

    class Convert < Thor
      extend ThorExt::Start
      desc "jekyll SITE_DIRECTORY OUTPUT_DIRECTORY", "Convert a Jekyll site directory to a Capsium package"
      def jekyll(site_directory, output_directory)
        converter = Capsium::Converters::Jekyll.new(site_directory, output_directory)
        converter.convert
      end
    end

    desc "package SUBCOMMAND ...ARGS", "Manage packages"
    subcommand "package", Capsium::Cli::Package

    desc "reactor SUBCOMMAND ...ARGS", "Manage the reactor"
    subcommand "reactor", Capsium::Cli::Reactor

    desc "converter SUBCOMMAND ...ARGS", "Convert from another format"
    subcommand "converter", Capsium::Cli::Convert
  end
end
