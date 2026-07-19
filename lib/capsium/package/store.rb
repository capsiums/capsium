# frozen_string_literal: true

require "fileutils"
require "json"
require "zip"

module Capsium
  class Package
    # A package store directory (ARCHITECTURE.md section 4a): a directory
    # of "<name>-<version>.cap" files plus an optional index.json mapping
    # dependency GUID -> file name. Dependencies resolve to the newest
    # version satisfying their semver range; an index.json entry pins the
    # GUID to a specific file (still range-checked).
    class Store
      INDEX_FILE = "index.json"
      CAP_GLOB = "*.cap"

      # One store .cap with its identity per its metadata.json.
      CatalogEntry = Data.define(:path, :guid, :version)

      attr_reader :dir

      # The store configured via the CAPSIUM_STORE environment variable,
      # or nil when unset.
      def self.default
        dir = ENV.fetch("CAPSIUM_STORE", nil)
        dir.nil? || dir.empty? ? nil : new(dir)
      end

      def initialize(dir)
        unless File.directory?(dir)
          raise DependencyError, "Package store directory not found: #{dir}"
        end

        @dir = dir
      end

      # The newest .cap providing the dependency GUID whose version
      # satisfies the range string.
      def find(guid, range_string)
        range = VersionRange.parse(range_string)
        indexed = indexed_path(guid)
        return indexed_satisfying(indexed, guid, range_string, range) if indexed

        candidates = catalog.select { |entry| entry.guid == guid }
        if candidates.empty?
          raise DependencyNotFoundError,
                "no package for dependency #{guid} in store #{@dir}"
        end

        satisfying = candidates.select { |entry| range.satisfied_by?(entry.version) }
        return satisfying.max_by(&:version).path unless satisfying.empty?

        versions = candidates.map { |entry| entry.version.to_s }.sort.join(", ")
        raise UnsatisfiableDependencyError,
              "no version of #{guid} satisfies '#{range_string}' " \
              "(store has: #{versions})"
      end

      # Every .cap in the store with its metadata identity (memoized).
      def catalog
        @catalog ||= Dir.glob(File.join(@dir, CAP_GLOB)).map do |path|
          catalog_entry(path)
        end
      end

      # Installs the .cap at source_path into the store as file_name
      # (conventionally "<name>-<version>.cap"), records guid ->
      # file_name in index.json (atomically, tmp + rename) and returns
      # the installed path. Used by registry installs
      # (Capsium::Registry#install).
      def install(source_path, guid:, file_name:)
        destination = File.join(@dir, file_name)
        tmp = "#{destination}.tmp-#{Process.pid}"
        FileUtils.cp(source_path, tmp)
        File.rename(tmp, destination)
        record_index(guid, file_name)
        destination
      end

      private

      # Records guid -> file_name in the store's index.json and drops
      # the memoized catalog so the new .cap is found.
      def record_index(guid, file_name)
        index = load_index.merge(guid => file_name)
        path = File.join(@dir, INDEX_FILE)
        tmp = "#{path}.tmp-#{Process.pid}"
        File.write(tmp, JSON.pretty_generate(index))
        File.rename(tmp, path)
        @load_index = index
        @catalog = nil
      end

      def indexed_path(guid)
        file = load_index[guid]
        file && File.join(@dir, file)
      end

      def indexed_satisfying(path, guid, range_string, range)
        unless File.file?(path)
          raise DependencyNotFoundError,
                "#{INDEX_FILE} maps #{guid} to a missing file: #{path}"
        end

        entry = catalog_entry(path)
        return entry.path if range.satisfied_by?(entry.version)

        raise UnsatisfiableDependencyError,
              "indexed #{guid} #{entry.version} does not satisfy '#{range_string}'"
      end

      def catalog_entry(cap_path)
        metadata = read_metadata(cap_path)
        CatalogEntry.new(path: cap_path, guid: metadata["guid"],
                         version: Version.parse(metadata["version"].to_s))
      end

      def read_metadata(cap_path)
        Zip::File.open(cap_path) do |zip|
          entry = zip.find_entry(Package::METADATA_FILE)
          raise DependencyError, "no #{Package::METADATA_FILE} in #{cap_path}" unless entry

          JSON.parse(entry.get_input_stream.read)
        end
      end

      def load_index
        @load_index ||= begin
          path = File.join(@dir, INDEX_FILE)
          File.file?(path) ? JSON.parse(File.read(path)) : {}
        end
      end
    end
  end
end
