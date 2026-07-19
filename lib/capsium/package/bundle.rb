# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "zip"

module Capsium
  class Package
    # Bundled dependencies of an encapsulated (self-contained) package
    # (ARCHITECTURE.md section 4a extension): dependency .cap files
    # embedded under packages/ with a packages/index.json manifest
    # mapping each dependency GUID to its file, version and SHA-256:
    #
    #   packages/
    #     index.json                # guid => {"file", "version", "sha256"}
    #     <name>-<version>.cap      # one per declared dependency
    #
    # One-level bundling policy: only the dependencies DECLARED in the
    # package's own metadata.dependencies are bundled; to make a whole
    # tree self-contained the parent must declare the transitive
    # closure. At load time bundled dependencies resolve FIRST, before
    # the store -> registry chain, and a package's bundle is passed down
    # to its dependencies so their re-declared dependencies resolve from
    # it too (recursive-capable).
    #
    # Security: bundled .cap files are covered by the parent package's
    # security.json checksums like every other file; the manifest
    # SHA-256 is re-verified when a bundled dependency is resolved, and
    # each bundled package's own security.json is verified when it is
    # loaded (the usual Capsium::Package activation checks).
    class Bundle
      DIRECTORY = "packages"
      INDEX_FILE = "packages/index.json"

      # One bundled dependency: the absolute .cap path, its version and
      # the SHA-256 recorded in the manifest.
      Entry = Data.define(:file, :version, :sha256)

      attr_reader :entries

      def initialize(package_path, entries = nil)
        @entries = entries || load_entries(package_path)
      end

      # Embeds the resolved dependency .cap files (guid => .cap path
      # pairs, in declaration order) into the package directory at
      # package_path: copies each under packages/ and writes the
      # packages/index.json manifest. Returns the manifest hash.
      def self.write(package_path, resolutions)
        FileUtils.mkdir_p(File.join(package_path, DIRECTORY))
        index = resolutions.to_h do |guid, cap_path|
          file = File.join(DIRECTORY, File.basename(cap_path))
          FileUtils.cp(cap_path, File.join(package_path, file))
          [guid, { "file" => file,
                   "version" => cap_version(cap_path),
                   "sha256" => Digest::SHA256.file(cap_path).hexdigest }]
        end
        File.write(File.join(package_path, INDEX_FILE), JSON.pretty_generate(index))
        index
      end

      def self.cap_version(cap_path)
        Zip::File.open(cap_path) do |zip|
          entry = zip.find_entry(METADATA_FILE)
          raise DependencyError, "no #{METADATA_FILE} in #{cap_path}" unless entry

          JSON.parse(entry.get_input_stream.read)["version"].to_s
        end
      end
      private_class_method :cap_version

      # Whether this bundle embeds any dependency.
      def present? = !@entries.empty?

      # Merges an inherited (ancestor) bundle underneath this one; own
      # entries win on GUID conflicts. Entries carry absolute paths, so
      # merged entries keep pointing into their source packages.
      def merged_with(other)
        return self if other.nil? || !other.present?
        return other unless present?

        self.class.new(nil, other.entries.merge(@entries))
      end

      # The absolute .cap path for a bundled dependency, or nil when the
      # GUID is not bundled (the caller falls back to the store ->
      # registry chain). Raises CircularDependencyError when the GUID is
      # already being resolved up-chain, UnsatisfiableDependencyError
      # when the bundled version does not satisfy the declared range and
      # Security::IntegrityError when the bundled file fails the
      # manifest SHA-256.
      def resolve_path(guid, range, chain:)
        entry = @entries[guid]
        return nil if entry.nil?

        if chain.include?(guid)
          raise CircularDependencyError,
                "circular dependency: #{(chain + [guid]).join(' -> ')}"
        end

        unless VersionRange.parse(range).satisfied_by?(Version.parse(entry.version))
          raise UnsatisfiableDependencyError,
                "bundled #{guid} #{entry.version} does not satisfy '#{range}'"
        end

        verify_sha256(guid, entry)
        entry.file
      end

      private

      def verify_sha256(guid, entry)
        actual = Digest::SHA256.file(entry.file).hexdigest
        return if actual == entry.sha256

        raise Security::IntegrityError,
              "bundled package failed manifest SHA-256 verification: " \
              "#{guid} (#{entry.file})"
      end

      def load_entries(package_path)
        index_path = File.join(package_path, INDEX_FILE)
        return {} unless File.file?(index_path)

        JSON.parse(File.read(index_path)).to_h do |guid, entry|
          [guid, Entry.new(file: File.join(package_path, entry.fetch("file")),
                           version: entry.fetch("version"),
                           sha256: entry.fetch("sha256"))]
        end
      rescue JSON::ParserError, KeyError => e
        raise DependencyError, "invalid #{INDEX_FILE}: #{e.message}"
      end
    end
  end
end
