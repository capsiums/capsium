# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"

module Capsium
  class Package
    autoload :Dataset, "capsium/package/dataset"
    autoload :DatasetConfig, "capsium/package/storage_config"
    autoload :DigitalSignatures, "capsium/package/security_config"
    autoload :IntegrityChecks, "capsium/package/security_config"
    autoload :Manifest, "capsium/package/manifest"
    autoload :ManifestConfig, "capsium/package/manifest_config"
    autoload :Metadata, "capsium/package/metadata"
    autoload :MetadataData, "capsium/package/metadata_config"
    autoload :Repository, "capsium/package/metadata_config"
    autoload :Resource, "capsium/package/manifest_config"
    autoload :Route, "capsium/package/routes_config"
    autoload :Routes, "capsium/package/routes"
    autoload :RoutesConfig, "capsium/package/routes_config"
    autoload :Security, "capsium/package/security"
    autoload :SecurityConfig, "capsium/package/security_config"
    autoload :SecurityData, "capsium/package/security_config"
    autoload :Signer, "capsium/package/signer"
    autoload :Storage, "capsium/package/storage"
    autoload :StorageConfig, "capsium/package/storage_config"
    autoload :StorageData, "capsium/package/storage_config"
    autoload :Validator, "capsium/package/validator"

    attr_reader :name, :path, :manifest, :metadata, :routes, :storage,
                :security, :load_type

    MANIFEST_FILE = "manifest.json"
    METADATA_FILE = "metadata.json"
    STORAGE_FILE = "storage.json"
    ROUTES_FILE = "routes.json"
    SECURITY_FILE = "security.json"
    SIGNATURE_FILE = "signature.sig"
    CONTENT_DIR = "content"
    DATA_DIR = "data"

    def initialize(path, load_type: nil)
      @original_path = Pathname.new(path).expand_path
      @path = prepare_package(@original_path).to_s
      @load_type = load_type || determine_load_type(path)
      create_package_structure
      load_package
      @name = metadata.name
      verify_integrity!
      verify_signature!
    end

    def prepare_package(path)
      return path if File.directory?(path)

      if File.file?(path)
        return decompress_cap_file(path) if File.extname(path) == ".cap"

        raise Error, "The package must have a .cap extension"
      end

      raise Error, "Invalid package path: #{path}"
    end

    def solidify
      @manifest.save_to_file
      @metadata.save_to_file
      @routes.save_to_file
      @storage.save_to_file unless @storage.empty?
    end

    def decompress_cap_file(file_path)
      package_path = File.join(Dir.mktmpdir, package_stem(file_path))
      FileUtils.mkdir_p(package_path)
      Packager.new.unpack(file_path, package_path)
      package_path
    end

    def load_package
      # Mandatory
      @metadata = Metadata.new(metadata_path)

      # Optional
      @manifest = Manifest.new(manifest_path)
      @storage = Storage.new(storage_path)
      @routes = Routes.new(routes_path, @manifest, @storage)
      @security = Security.new(security_path)
    end

    def cleanup
      return unless @path != @original_path.to_s && File.directory?(@path)

      FileUtils.remove_entry(@path)
    end

    def datasets
      storage.datasets
    end

    # The .cap file this package was loaded from, or nil when loaded
    # from a directory.
    def cap_file_path
      @original_path.to_s if load_type == :cap_file
    end

    def content_files
      Dir.glob(File.join(content_path, "**", "*")).select do |file|
        File.file?(file)
      end
    end

    def determine_load_type(path)
      return :directory if File.directory?(path)
      return :cap_file if File.extname(path) == ".cap"

      :unsaved
    end

    # Verifies the package against security.json (ARCHITECTURE.md section
    # 6). Returns a list of typed errors; empty when no security.json is
    # present or all checksums match.
    def verify_integrity
      return [] unless @security.present?

      @security.verify(@path)
    end

    def verify_integrity!
      @security.verify!(@path) if @security.present?
    end

    # Whether security.json declares a digital signature for this package.
    def signed? = @security.signed?

    # Verifies the declared digital signature (RSA-SHA256) against the
    # checksum-covered payload. True when the package is unsigned (nothing
    # declared) or the signature verifies; false on mismatch.
    def verify_signature
      !signed? || Signer.new(@path).verify
    end

    def verify_signature!
      Signer.new(@path).verify! if signed?
    end

    private

    def package_stem(file_path)
      File.basename(file_path, ".cap")
    end

    def create_package_structure
      FileUtils.mkdir_p(@path)
      FileUtils.mkdir_p(content_path)
      FileUtils.mkdir_p(data_path)
    end

    def content_path = File.join(@path, CONTENT_DIR)

    def data_path = File.join(@path, DATA_DIR)

    def routes_path = File.join(@path, ROUTES_FILE)

    def storage_path = File.join(@path, STORAGE_FILE)

    def metadata_path = File.join(@path, METADATA_FILE)

    def manifest_path = File.join(@path, MANIFEST_FILE)

    def security_path = File.join(@path, SECURITY_FILE)
  end
end
