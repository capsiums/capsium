# frozen_string_literal: true

require "json"

module Capsium
  class Cli
    class Package < Thor
      extend ThorExt::Start
      include Formatting

      desc "info PACKAGE_PATH", "Display information about the package"
      option :store, type: :string, desc: "Package store directory (default: CAPSIUM_STORE)"

      def info(path_to_package)
        package = Capsium::Package.new(path_to_package, store: options[:store])
        puts "Package Path: #{package.path}"
        puts "Routes: #{package.routes.to_hash}"
        puts "Manifest: #{package.manifest.to_hash}"
        print_dependency_tree(package)
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

      desc "push PACKAGE_FILE", "Push a .cap into a static registry directory"
      option :registry, type: :string,
                        desc: "Registry directory (default: CAPSIUM_REGISTRY)"

      def push(path_to_package)
        registry = Capsium::Registry.fetch(options[:registry] || ENV.fetch("CAPSIUM_REGISTRY", nil))
        entry = registry.push(path_to_package)
        puts "Pushed #{entry.name} #{entry.version} to #{registry.location}"
      rescue Capsium::Registry::RegistryError => e
        raise Thor::Error, e.message
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
        Capsium::Package::Signer.sign_package(path_to_package, options[:key], options[:cert])
        puts "Package signed: #{path_to_package}"
      end

      desc "verify-signature PACKAGE_PATH [--cert CERT.pem]",
           "Verify the package digital signature declared in security.json"
      option :cert, type: :string,
                    desc: "Path to the X.509 certificate or public key PEM " \
                          "(defaults to the key embedded in the package)"

      def verify_signature(path_to_package)
        unless Capsium::Package::Signer.verify_package(path_to_package, options[:cert])
          raise Thor::Error, "Signature verification failed: #{path_to_package}"
        end

        puts "Signature valid: #{path_to_package}"
      rescue Capsium::Package::Signer::SignatureError => e
        raise Thor::Error, e.message
      end

      desc "encrypt PACKAGE_PATH --public-key PUB.pem -o OUT.cap",
           "Encrypt a package (AES-256-GCM, RSA-OAEP-SHA256 wrapped DEK)"
      option :public_key, type: :string, required: true,
                          desc: "Path to the recipient RSA public key or X.509 certificate PEM"
      option :output, type: :string, required: true, aliases: "-o",
                      desc: "Output path for the encrypted .cap"

      def encrypt(path_to_package)
        Capsium::Package::Cipher.new.encrypt(
          path_to_package, options[:public_key], options[:output]
        )
        puts "Package encrypted: #{options[:output]}"
      end

      desc "decrypt PACKAGE_PATH --private-key PRIV.pem [-o OUT.cap]",
           "Decrypt an encrypted package"
      option :private_key, type: :string, required: true,
                           desc: "Path to the recipient RSA private key PEM"
      option :output, type: :string, aliases: "-o",
                      desc: "Output path (default: <name>-decrypted.cap)"

      def decrypt(path_to_package)
        output = options[:output] || "#{File.basename(path_to_package, '.cap')}-decrypted.cap"
        Capsium::Package::Cipher.new.decrypt(path_to_package, options[:private_key], output)
        puts "Package decrypted: #{output}"
      end

      desc "test PACKAGE_PATH", "Run the package's tests/*.yaml suite (05x-testing DSL)"

      def test(path_to_package)
        package = Capsium::Package.new(path_to_package)
        report = Capsium::Package::Testing::TestSuite.new(package).run
        report.results.each { |result| puts format_result(result) }
        if report.results.empty?
          puts "No tests found (#{Capsium::Package::Testing::TestSuite::TESTS_DIR}/*.yaml)"
        end
        puts report.summary
        raise Thor::Error, "Package tests failed" unless report.ok?
      end
    end
  end
end
