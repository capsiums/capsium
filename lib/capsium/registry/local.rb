# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Capsium
  class Registry
    # A static registry in a local directory (read-write). Push
    # validates the .cap (Capsium::Package::Validator), copies it into
    # the registry directory and atomically rewrites index.json
    # (tmp + rename) with recomputed sha256 and size.
    class Local < Registry
      attr_reader :dir

      def initialize(dir)
        super()
        if File.exist?(dir) && !File.directory?(dir)
          raise InvalidRegistryError, "registry path is not a directory: #{dir}"
        end

        @dir = dir
      end

      def location = dir

      # Validates cap_path, copies it into the registry as
      # "<name>-<version>.cap" and records it in index.json. Returns the
      # recorded Entry. Raises InvalidPackageError when the package
      # fails validation.
      def push(cap_path)
        validate_package!(cap_path)
        entry = build_entry(read_metadata(cap_path), cap_path)
        FileUtils.mkdir_p(dir)
        atomic_copy(cap_path, File.join(dir, entry.file))
        record(entry)
        entry
      end

      private

      def index
        @index ||= begin
          path = File.join(dir, INDEX_FILE)
          File.file?(path) ? parse_index(File.read(path)) : { "packages" => {} }
        end
      end

      def with_entry_file(entry)
        path = File.join(dir, entry.file)
        unless File.file?(path)
          raise InvalidRegistryError, "#{location}: indexed file missing: #{entry.file}"
        end

        yield path
      end

      def validate_package!(cap_path)
        raise InvalidPackageError, "not a file: #{cap_path}" unless File.file?(cap_path)

        failures = Package::Validator.new(cap_path).run.reject(&:ok?)
        return if failures.empty?

        details = failures.flat_map do |failure|
          failure.messages.map { |message| "#{failure.name}: #{message}" }
        end
        raise InvalidPackageError,
              "package validation failed for #{cap_path} — #{details.join('; ')}"
      end

      def read_metadata(cap_path)
        Packager.new.with_unpacked_cap(cap_path) do |unpacked|
          JSON.parse(File.read(File.join(unpacked, Package::METADATA_FILE)))
        end
      end

      def build_entry(metadata, cap_path)
        guid = metadata["guid"]
        name = metadata["name"]
        version = metadata["version"]
        unless guid.is_a?(String) && name.is_a?(String) && version.is_a?(String)
          raise InvalidPackageError, "metadata.json must declare guid, name and version"
        end

        Entry.new(guid: guid, name: name, version: parse_package_version(version),
                  file: "#{name}-#{version}.cap",
                  sha256: Digest::SHA256.file(cap_path).hexdigest,
                  size: File.size(cap_path))
      end

      def parse_package_version(string)
        Package::Version.parse(string)
      rescue Capsium::Error => e
        raise InvalidPackageError, "metadata.json version is invalid: #{e.message}"
      end

      def record(entry)
        listing = index["packages"][entry.guid] ||
                  { "name" => entry.name, "versions" => {} }
        listing["versions"][entry.version.to_s] = {
          "file" => entry.file, "sha256" => entry.sha256, "size" => entry.size
        }
        index["packages"][entry.guid] = listing
        atomic_write(File.join(dir, INDEX_FILE), JSON.pretty_generate(index))
      end

      def atomic_copy(source, destination)
        tmp = "#{destination}.tmp-#{Process.pid}"
        FileUtils.cp(source, tmp)
        File.rename(tmp, destination)
      end

      def atomic_write(path, content)
        tmp = "#{path}.tmp-#{Process.pid}"
        File.write(tmp, content)
        File.rename(tmp, path)
      end
    end
  end
end
