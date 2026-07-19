# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"

module Capsium
  class Package
    autoload :Cipher, "capsium/package/cipher"
    autoload :CircularDependencyError, "capsium/package/dependency_resolver"
    autoload :Composition, "capsium/package/composition"
    autoload :Dataset, "capsium/package/dataset"
    autoload :DatasetConfig, "capsium/package/storage_config"
    autoload :DependencyError, "capsium/package/dependency_resolver"
    autoload :DependencyNotFoundError, "capsium/package/dependency_resolver"
    autoload :DependencyResolver, "capsium/package/dependency_resolver"
    autoload :DependencyVisibilityError, "capsium/package/dependency_resolver"
    autoload :DigitalSignatures, "capsium/package/security_config"
    autoload :EncryptionConfig, "capsium/package/encryption_config"
    autoload :EncryptionEnvelope, "capsium/package/encryption_config"
    autoload :IntegrityChecks, "capsium/package/security_config"
    autoload :LayerConfig, "capsium/package/storage_config"
    autoload :Manifest, "capsium/package/manifest"
    autoload :ManifestConfig, "capsium/package/manifest_config"
    autoload :MergedView, "capsium/package/merged_view"
    autoload :Metadata, "capsium/package/metadata"
    autoload :MetadataData, "capsium/package/metadata_config"
    autoload :Preparation, "capsium/package/preparation"
    autoload :Repository, "capsium/package/metadata_config"
    autoload :ResolvedDependency, "capsium/package/dependency_resolver"
    autoload :Resource, "capsium/package/manifest_config"
    autoload :ResponseRewrite, "capsium/package/routes_config"
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
    autoload :Store, "capsium/package/store"
    autoload :Testing, "capsium/package/testing"
    autoload :UnsatisfiableDependencyError, "capsium/package/dependency_resolver"
    autoload :Validator, "capsium/package/validator"
    autoload :Verification, "capsium/package/verification"
    autoload :Version, "capsium/package/version"
    autoload :VersionRange, "capsium/package/version"

    include Verification
    include Composition
    include Preparation

    attr_reader :name, :path, :manifest, :metadata, :routes, :storage,
                :security, :load_type, :resolved_dependencies

    MANIFEST_FILE = "manifest.json"
    METADATA_FILE = "metadata.json"
    STORAGE_FILE = "storage.json"
    ROUTES_FILE = "routes.json"
    SECURITY_FILE = "security.json"
    SIGNATURE_FILE = "signature.sig"
    CONTENT_DIR = "content"
    DATA_DIR = "data"

    # Loads a package directory or .cap file. Composite packages
    # (metadata.dependencies, ARCHITECTURE.md section 4a) resolve against
    # the package store given as `store` (directory path or Store) or via
    # CAPSIUM_STORE. `dependency_chain` is internal: the ancestor GUIDs
    # used for circular-dependency detection during recursive resolution.
    def initialize(path, load_type: nil, decryption_key: nil, store: nil,
                   dependency_chain: [])
      @decryption_key = decryption_key
      @original_path = Pathname.new(path).expand_path
      @path = prepare_package(@original_path).to_s
      @load_type = load_type || determine_load_type(path)
      create_package_structure
      load_package
      @name = metadata.name
      @resolved_dependencies = resolve_dependencies(store, dependency_chain)
      validate_dependency_references!
      verify_integrity!
      verify_signature!
    end

    def solidify
      @manifest.save_to_file
      @metadata.save_to_file
      @routes.save_to_file
      @storage.save_to_file unless @storage.empty?
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
      @resolved_dependencies.each { |dependency| dependency.package.cleanup }
      FileUtils.remove_entry(@path) if @path != @original_path.to_s && File.directory?(@path)
    end

    def datasets = storage.datasets

    # The merged content view across the storage layers (ARCHITECTURE.md
    # section 5a); exported_only gives the dependent-package view (section 4a).
    # Resolved dependencies act as read-only layers below all own layers.
    def merged_view(exported_only: false)
      @merged_views ||= {}
      @merged_views[exported_only] ||=
        MergedView.new(@path, storage: @storage, manifest: @manifest,
                              dependency_views: dependency_views,
                              exported_only: exported_only)
    end

    # The .cap file this package was loaded from, or nil when loaded
    # from a directory.
    def cap_file_path
      @original_path.to_s if load_type == :cap_file
    end

    def content_files
      Dir.glob(File.join(content_path, "**", "*")).select { |file| File.file?(file) }
    end
  end
end
