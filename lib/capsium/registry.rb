# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Capsium
  # A static package registry: a directory or a static https base URL
  # holding an index.json plus .cap files stored relative to the
  # registry root, so any static host (GitHub Pages, S3, nginx) can
  # serve it. Index shape:
  #
  #   { "packages": { "<guid>": { "name": "story-of-claire",
  #     "versions": { "1.0.0": { "file": "story-of-claire-1.0.0.cap",
  #                              "sha256": "<hex>", "size": 642047 } } } } }
  #
  # Registry.fetch(ref) returns the implementation for a reference: a
  # Local directory (read-write) or a Remote http(s) base URL
  # (read-only). Both resolve and install; only Local pushes.
  class Registry
    autoload :Local, "capsium/registry/local"
    autoload :Remote, "capsium/registry/remote"

    INDEX_FILE = "index.json"
    ENV_VAR = "CAPSIUM_REGISTRY"

    # Base error for every registry failure.
    class RegistryError < Capsium::Error; end

    # No registry reference was given (neither flag nor CAPSIUM_REGISTRY).
    class RegistryNotConfiguredError < RegistryError; end

    # The registry itself is unusable (bad path or URL, unreadable index).
    class InvalidRegistryError < RegistryError; end

    # A .cap offered to push failed package validation.
    class InvalidPackageError < RegistryError; end

    # The index has no entry for the requested package GUID.
    class PackageNotFoundError < RegistryError; end

    # The registry has the GUID but no version satisfies the constraint.
    class UnsatisfiableConstraintError < RegistryError; end

    # A fetched .cap does not match the sha256 declared in the index.
    class ChecksumMismatchError < RegistryError; end

    # A registry file could not be retrieved (network or HTTP failure).
    class FetchError < RegistryError; end

    # One indexed version of a registry package.
    Entry = Data.define(:guid, :name, :version, :file, :sha256, :size) do
      # The canonical store file name for this entry's .cap.
      def cap_file_name = "#{name}-#{version}.cap"
    end

    class << self
      # The registry at the given reference: a Local directory or a
      # Remote http(s) base URL. Raises RegistryNotConfiguredError when
      # no reference is given.
      def fetch(ref)
        if ref.nil? || ref.to_s.empty?
          raise RegistryNotConfiguredError,
                "no registry configured (pass --registry or set #{ENV_VAR})"
        end

        ref.to_s.match?(%r{\Ahttps?://}) ? Remote.new(ref.to_s) : Local.new(ref.to_s)
      end

      # The registry named by the CAPSIUM_REGISTRY environment variable,
      # or nil when unset.
      def default
        ref = ENV.fetch(ENV_VAR, nil)
        ref.nil? || ref.empty? ? nil : fetch(ref)
      end
    end

    def initialize
      @index = nil
    end

    # Where this registry lives (directory path or base URL), for
    # messages and reports.
    def location = raise(NotImplementedError)

    # The newest indexed version of the package GUID satisfying the
    # semver constraint (default "*"). Raises PackageNotFoundError or
    # UnsatisfiableConstraintError.
    def resolve(guid, constraint = "*")
      listing = packages[guid]
      raise PackageNotFoundError, "no package #{guid} in registry #{location}" if listing.nil?

      versions = listing_versions(guid, listing)
      range = Package::VersionRange.parse(constraint)
      satisfying = versions.keys.select { |version| range.satisfied_by?(version) }
      raise_unsatisfiable(guid, constraint, versions) if satisfying.empty?

      entry_for(guid, listing, satisfying.max)
    end

    # Resolves the newest satisfying version, fetches its .cap (verifying
    # the sha256 declared in the index) and installs it into the package
    # store as "<name>-<version>.cap". Returns the installed store path.
    def install(guid, constraint = "*", store:)
      entry = resolve(guid, constraint)
      with_entry_file(entry) do |path|
        verify_checksum!(entry, path)
        store_for(store).install(path, guid: entry.guid, file_name: entry.cap_file_name)
      end
    end

    # Only Local registries are writable; Remote overrides nothing.
    def push(_cap_path)
      raise RegistryError, "registry is read-only: #{location}"
    end

    private

    # Subclass hooks: the parsed index.json hash, and a yield of a local
    # filesystem path holding the entry's .cap bytes.
    def index = raise(NotImplementedError)

    def with_entry_file(entry) = raise(NotImplementedError)

    def packages
      all = index["packages"]
      unless all.is_a?(Hash)
        raise InvalidRegistryError, "#{location}: #{INDEX_FILE} has no \"packages\" object"
      end

      all
    end

    def parse_index(json_text)
      JSON.parse(json_text)
    rescue JSON::ParserError => e
      raise InvalidRegistryError, "#{location}: #{INDEX_FILE} is not valid JSON: #{e.message}"
    end

    def listing_versions(guid, listing)
      versions = listing["versions"]
      unless versions.is_a?(Hash) && !versions.empty?
        raise InvalidRegistryError, "#{location}: no versions indexed for #{guid}"
      end

      versions.to_h { |string, data| [parse_index_version(guid, string), data] }
    end

    def parse_index_version(guid, string)
      Package::Version.parse(string)
    rescue Capsium::Error
      raise InvalidRegistryError, "#{location}: invalid version #{string.inspect} for #{guid}"
    end

    def raise_unsatisfiable(guid, constraint, versions)
      available = versions.keys.map(&:to_s).sort.join(", ")
      raise UnsatisfiableConstraintError,
            "no version of #{guid} satisfies '#{constraint}' (registry has: #{available})"
    end

    def entry_for(guid, listing, version)
      data = listing.fetch("versions").fetch(version.to_s)
      unless data["file"].is_a?(String) && data["sha256"].is_a?(String)
        raise InvalidRegistryError,
              "#{location}: incomplete index entry for #{guid} #{version} (file/sha256)"
      end

      Entry.new(guid: guid, name: listing["name"].to_s, version: version,
                file: data["file"], sha256: data["sha256"], size: data["size"].to_i)
    end

    def verify_checksum!(entry, path)
      actual = Digest::SHA256.file(path).hexdigest
      return if actual == entry.sha256.downcase

      raise ChecksumMismatchError,
            "sha256 mismatch for #{entry.cap_file_name} from #{location}: " \
            "index declares #{entry.sha256}, file hashes to #{actual}"
    end

    # A Store for the given Store or directory path (created when
    # missing, so installing into a fresh store directory works).
    def store_for(store)
      return store if store.is_a?(Package::Store)

      FileUtils.mkdir_p(store.to_s)
      Package::Store.new(store.to_s)
    end
  end
end
