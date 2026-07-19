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
      end

      desc "unpack PACKAGE_FILE", "Unpack a .cap package into a directory"
      option :output, type: :string, aliases: "-o", desc: "Output directory"

      def unpack(path_to_package)
        destination = options[:output] || File.basename(path_to_package, ".cap")
        Capsium::Packager.new.unpack(path_to_package, destination)
        puts "Package unpacked to: #{destination}"
      end

      desc "validate PACKAGE_PATH", "Validate a package directory or .cap file"

      def validate(path_to_package)
        results = Capsium::Package::Validator.new(path_to_package).run
        results.each { |result| puts format_result(result) }
        return if results.all?(&:ok?)

        raise Thor::Error, "Package validation failed"
      end

      private

      def format_result(result)
        line = "#{result.ok? ? 'PASS' : 'FAIL'} #{result.name}"
        return line if result.messages.empty?

        "#{line}: #{result.messages.join('; ')}"
      end
    end
  end
end
