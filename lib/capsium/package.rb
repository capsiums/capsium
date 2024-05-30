# frozen_string_literal: true

# lib/capsium/package.rb
require "fileutils"
require "json"
require "yaml"
require "csv"
require "sqlite3"
require "zip"
require_relative "package/manifest"
require_relative "package/metadata"
require_relative "package/routes"
require_relative "package/dataset"
require_relative "package/storage"
require_relative "packager"

module Capsium
  class Package
    attr_reader :name, :path, :manifest, :metadata, :routes, :datasets, :storage

    MANIFEST_FILE = "manifest.json"
    METADATA_FILE = "metadata.json"
    PACKAGING_FILE = "packaging.json"
    SIGNATURE_FILE = "signature.json"
    STORAGE_FILE = "storage.json"
    ROUTES_FILE = "routes.json"
    CONTENT_DIR = "content"
    DATA_DIR = "data"
    ENCRYPTED_PACKAGING_FILE = "package.enc"

    def initialize(path)
      @original_path = path
      @path = prepare_package(path)
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
      Zip::File.open(file_path) do |zip_file|
        zip_file.each do |entry|
          entry_path = File.join(temp_dir, entry.name)
          FileUtils.mkdir_p(File.dirname(entry_path))
          entry.extract(entry_path)
        end
      end
      temp_dir
    end

    def load_package
      @manifest = Manifest.new(manifest_path)
      @metadata = Metadata.new(metadata_path)
      @routes = Routes.new(routes_path, @manifest)
      @storage = Storage.new(storage_path)
      # @datasets = load_datasets
    end

    def cleanup
      return unless @path != @original_path && File.directory?(@path)

      FileUtils.remove_entry(@path)
    end

    def package_files
      @packager.package_files
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
