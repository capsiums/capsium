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
      option :bundle_deps, type: :boolean, default: false, aliases: "--bundle",
                           desc: "Embed the resolved dependencies under packages/ " \
                                 "so the .cap activates with no store or registry"
      option :store, type: :string, desc: "Package store directory (default: CAPSIUM_STORE)"
      option :registry, type: :string, desc: "Registry reference (default: CAPSIUM_REGISTRY)"

      def pack(path_to_package)
        package = Capsium::Package.new(path_to_package, store: options[:store])
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

      desc "sign PACKAGE_PATH --key KEY [--cert CERT.pem] [--openpgp]",
           "Sign the package (RSA-SHA256/X.509, or OpenPGP) into security.json"
      option :key, type: :string, required: true,
                   desc: "RSA private key PEM (min 2048 bits); OpenPGP secret key with --openpgp"
      option :cert, type: :string, desc: "X.509 certificate PEM (must match the key)"
      option :openpgp, type: :boolean, default: false, desc: "OpenPGP detached signature"

      def sign(path_to_package)
        if options[:openpgp] && options[:cert]
          raise Thor::Error, "--cert is only used with X.509 signing"
        end

        if options[:openpgp]
          Capsium::Package::OpenPgpSigner.sign_package(path_to_package, options[:key])
        else
          Capsium::Package::Signer.sign_package(path_to_package, options[:key], options[:cert])
        end
        puts "Package signed: #{path_to_package}"
      end

      desc "verify-signature PACKAGE_PATH [--cert CERT-or-PUB] [--openpgp]",
           "Verify the declared digital signature (auto-detected from security.json)"
      option :cert, type: :string, desc: "certificate or public key (default: embedded)"
      option :openpgp, type: :boolean, default: false, desc: "verify as OpenPGP"

      def verify_signature(path_to_package)
        verifier = options[:openpgp] ? Capsium::Package::OpenPgpSigner : Capsium::Package::Signer
        unless verifier.verify_package(path_to_package, options[:cert])
          raise Thor::Error, "Signature verification failed: #{path_to_package}"
        end

        puts "Signature valid: #{path_to_package}"
      rescue Capsium::Package::Signer::SignatureError => e
        raise Thor::Error, e.message
      end

      desc "encrypt PACKAGE_PATH -o OUT.cap [--public-key PUB.pem | --openpgp --recipient PUB]",
           "Encrypt a package (AES-256-GCM; RSA or OpenPGP key management)"
      option :public_key, type: :string, desc: "recipient RSA public key or X.509 certificate PEM"
      option :recipient, type: :string, desc: "recipient OpenPGP public key (with --openpgp)"
      option :openpgp, type: :boolean, default: false, desc: "encrypt for an OpenPGP recipient"
      option :output, type: :string, required: true, aliases: "-o",
                      desc: "Output path for the encrypted .cap"

      def encrypt(path_to_package)
        key = options[:public_key] || options[:recipient]
        raise Thor::Error, "encrypt requires --public-key or --openpgp --recipient" if key.nil?

        cipher = options[:openpgp] ? Capsium::Package::OpenPgpCipher.new : Capsium::Package::Cipher.new
        cipher.encrypt(path_to_package, key, options[:output])
        puts "Package encrypted: #{options[:output]}"
      end

      desc "decrypt PACKAGE_PATH [--private-key PRIV.pem | --openpgp --key SEC.asc] [-o OUT.cap]",
           "Decrypt an encrypted package (key management auto-detected from the envelope)"
      option :private_key, type: :string, desc: "recipient RSA private key PEM"
      option :key, type: :string, desc: "recipient OpenPGP secret key"
      option :openpgp, type: :boolean, default: false, desc: "decrypt with an OpenPGP key"
      option :output, type: :string, aliases: "-o",
                      desc: "Output path (default: <name>-decrypted.cap)"

      def decrypt(path_to_package)
        key = options[:private_key] || options[:key]
        raise Thor::Error, "decrypt requires --private-key (RSA) or --key (OpenPGP)" if key.nil?

        output = options[:output] || "#{File.basename(path_to_package, '.cap')}-decrypted.cap"
        cipher = if options[:openpgp]
                   Capsium::Package::OpenPgpCipher.new
                 else
                   Capsium::Package::Cipher.for_encrypted(path_to_package)
                 end
        cipher.decrypt(path_to_package, key, output)
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
