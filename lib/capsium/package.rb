# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"
require "zip"

module Capsium
  class Package
    autoload :Dataset, "capsium/package/dataset"
    autoload :DatasetConfig, "capsium/package/dataset_config"
    autoload :Dependency, "capsium/package/metadata_config"
    autoload :Manifest, "capsium/package/manifest"
    autoload :ManifestConfig, "capsium/package/manifest_config"
    autoload :ManifestConfigItem, "capsium/package/manifest_config"
    autoload :Metadata, "capsium/package/metadata"
    autoload :MetadataData, "capsium/package/metadata_config"
    autoload :Route, "capsium/package/routes_config"
    autoload :RouteTarget, "capsium/package/routes_config"
    autoload :Routes, "capsium/package/routes"
    autoload :RoutesConfig, "capsium/package/routes_config"
    autoload :Storage, "capsium/package/storage"
    autoload :StorageConfig, "capsium/package/storage_config"

    attr_reader :name, :path, :manifest, :metadata, :routes, :storage,
                :load_type

    MANIFEST_FILE = "manifest.json"
    METADATA_FILE = "metadata.json"
    PACKAGING_FILE = "packaging.json"
    SIGNATURE_FILE = "signature.json"
    STORAGE_FILE = "storage.json"
    ROUTES_FILE = "routes.json"
    CONTENT_DIR = "content"
    DATA_DIR = "data"
    ENCRYPTED_PACKAGING_FILE = "package.enc"

    def initialize(path, load_type: nil)
      @original_path = Pathname.new(path).expand_path
      @path = prepare_package(@original_path)
      @load_type = load_type || determine_load_type(path)
      create_package_structure
      load_package
      @name = metadata.name
    end

    def prepare_package(path)
      return path if File.directory?(path)

      if File.file?(path)
        return decompress_cap_file(path) if File.extname(path) == ".cap"

        raise "Error: The package must have a .cap extension"
      end

      raise "Invalid package path: #{path}"
    end

    def solidify
      @manifest.save_to_file
      @metadata.save_to_file
      @routes.save_to_file
      @storage.save_to_file
    end

    def decompress_cap_file(file_path)
      temp_dir = Dir.mktmpdir
      metadata_path = File.join(temp_dir, METADATA_FILE)

      # Extract metadata.json first
      Zip::File.open(file_path) do |zip_file|
        if (entry = zip_file.find_entry(METADATA_FILE))
          entry.extract(metadata_path)
        end
      end

      metadata = Metadata.new(metadata_path)
      package_name = metadata.name
      package_version = metadata.version

      package_path = File.join(temp_dir, "#{package_name}-#{package_version}")
      FileUtils.mkdir_p(package_path)

      Zip::File.open(file_path) do |zip_file|
        zip_file.each do |entry|
          entry_path = File.join(package_path, entry.name)
          FileUtils.mkdir_p(File.dirname(entry_path))
          entry.extract(entry_path)
        end
      end

      package_path
    end

    def load_package
      # Mandatory
      @metadata = Metadata.new(metadata_path)

      # Optional
      @manifest = Manifest.new(manifest_path)
      @storage = Storage.new(storage_path)
      @routes = Routes.new(routes_path, @manifest, @storage)
    end

    def cleanup
      return unless @path != @original_path && File.directory?(@path)

      FileUtils.remove_entry(@path)
    end

    def datasets
      storage.datasets
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

    private

    def create_package_structure
      FileUtils.mkdir_p(@path)
      FileUtils.mkdir_p(content_path)
      FileUtils.mkdir_p(data_path)
    end

    def content_path
      File.join(@path, CONTENT_DIR)
    end

    def data_path
      File.join(@path, DATA_DIR)
    end

    def routes_path
      File.join(@path, ROUTES_FILE)
    end

    def storage_path
      File.join(@path, STORAGE_FILE)
    end

    def metadata_path
      File.join(@path, METADATA_FILE)
    end

    def manifest_path
      File.join(@path, MANIFEST_FILE)
    end
  end
end
