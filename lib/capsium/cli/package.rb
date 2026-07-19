# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

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

      desc "sign PACKAGE_PATH --key KEY.pem [--cert CERT.pem]",
           "Sign the package (RSA-SHA256) and record the signature in security.json"
      option :key, type: :string, required: true,
                   desc: "Path to the RSA private key PEM (min 2048 bits)"
      option :cert, type: :string,
                    desc: "Path to the X.509 certificate PEM (must match the key)"

      def sign(path_to_package)
        if File.extname(path_to_package) == ".cap"
          sign_cap_file(path_to_package)
        else
          Capsium::Package::Signer.new(path_to_package).sign(options[:key], options[:cert])
        end
        puts "Package signed: #{path_to_package}"
      end

      desc "verify-signature PACKAGE_PATH [--cert CERT.pem]",
           "Verify the package digital signature declared in security.json"
      option :cert, type: :string,
                    desc: "Path to the X.509 certificate or public key PEM " \
                          "(defaults to the key embedded in the package)"

      def verify_signature(path_to_package)
        with_package_directory(path_to_package) do |directory|
          signer = Capsium::Package::Signer.new(directory)
          raise Thor::Error, "Package is not signed" unless signer.signed?
          unless signer.verify(options[:cert])
            raise Thor::Error, "Signature verification failed: #{path_to_package}"
          end

          puts "Signature valid: #{path_to_package}"
        end
      end

      private

      def sign_cap_file(cap_path)
        Dir.mktmpdir do |dir|
          Capsium::Packager.new.unpack(cap_path, dir)
          Capsium::Package::Signer.new(dir).sign(options[:key], options[:cert])
          repack(dir, cap_path)
        end
      end

      def repack(directory, cap_path)
        Dir.mktmpdir do |tmp|
          tmp_cap = File.join(tmp, File.basename(cap_path))
          # Loading verifies the freshly signed package before recompressing.
          package = Capsium::Package.new(directory)
          Capsium::Packager.new.compress_package(package, tmp_cap)
          FileUtils.mv(tmp_cap, cap_path)
        end
      end

      def with_package_directory(path_to_package)
        return yield path_to_package unless File.extname(path_to_package) == ".cap"

        Dir.mktmpdir do |dir|
          Capsium::Packager.new.unpack(path_to_package, dir)
          yield dir
        end
      end

      def format_result(result)
        line = "#{result.ok? ? 'PASS' : 'FAIL'} #{result.name}"
        return line if result.messages.empty?

        "#{line}: #{result.messages.join('; ')}"
      end
    end
  end
end
