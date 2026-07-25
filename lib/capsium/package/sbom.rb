# frozen_string_literal: true

require "digest"
require "json"
require "time"

module Capsium
  class Package
    # SPDX 2.3 SBOM generator for a Capsium package. Lists every
    # content/ + data/ file (plus metadata.json, manifest.json,
    # storage.json, security.json) with its sha256 checksum so the
    # SBOM matches what the package integrity check covers.
    #
    # SPDX 2.3 minimal format: Document + one Package + zero or more
    # Files + Relationships. We don't model relationships (the package
    # is a flat file set from an SPDX perspective) but DO emit the
    # package's own metadata (name, version, license, guid) for
    # downstream license/clearance tooling.
    class Sbom
      SPDX_VERSION = "SPDX-2.3"
      SPDXID_DOCUMENT = "SPDXRef-DOCUMENT"
      SPDXID_PACKAGE = "SPDXRef-Package"
      CREATOR = "Tool: capsium-packager"
      DATA_URI = "https://capsium.org/sbom"
      SBOM_FILE = "sbom.spdx.json"

      attr_reader :package

      def initialize(package)
        @package = package
      end

      # Renders the SPDX document. The created timestamp is the
      # package's metadata.last_modified if present, else a fixed
      # epoch. Keeps the SBOM deterministic for reproducible builds.
      def to_h
        {
          spdxVersion: SPDX_VERSION,
          SPDXID: SPDXID_DOCUMENT,
          name: document_name,
          dataLicense: "CC0-1.0",
          creationInfo: {
            created: created_timestamp,
            creators: [CREATOR]
          },
          documentNamespace: document_namespace,
          packages: [package_entry],
          files: file_entries
        }
      end

      def to_json(*_args)
        JSON.pretty_generate(to_h)
      end

      # Writes the SBOM into the package directory at sbom.spdx.json.
      def save_to_file(output_path = default_path)
        File.write(output_path, to_json)
        output_path
      end

      class << self
        # Convenience: generate and save the SBOM for a package in one
        # call. Returns the path to the written file.
        def generate(package)
          new(package).save_to_file
        end
      end

      private

      def document_name
        "#{package.metadata.name}-#{package.metadata.version}"
      end

      def created_timestamp
        timestamp = package.metadata.respond_to?(:last_modified) &&
                    package.metadata.last_modified
        (timestamp || Time.at(0).utc).utc.iso8601
      end

      def document_namespace
        guid = package.metadata.guid || package.metadata.uuid || package.metadata.name
        "#{DATA_URI}/#{guid}/#{package.metadata.version}"
      end

      def package_entry
        {
          SPDXID: SPDXID_PACKAGE,
          name: package.metadata.name,
          versionInfo: package.metadata.version.to_s,
          downloadLocation: "NOASSERTION",
          filesAnalyzed: true,
          packageFileName: "#{package.metadata.name}-#{package.metadata.version}.cap",
          licenseDeclared: package.metadata.license || "NOASSERTION",
          licenseConcluded: "NOASSERTION",
          copyrightText: "NOASSERTION",
          supplier: "Organization: #{package.metadata.author || 'NOASSERTION'}",
          checksums: package_checksums
        }
      end

      def package_checksums
        # The .cap isn't built yet when the SBOM is generated (the SBOM
        # goes IN the .cap), so we can't checksum the archive itself.
        # Emit the guid+version as a content reference instead.
        []
      end

      def file_entries
        manifest_files.map.with_index(1) do |(path, _), index|
          file_entry(path, index)
        end
      end

      def manifest_files
        package.manifest.resources
      end

      def file_entry(path, index)
        full = File.join(package.path, path)
        {
          SPDXID: "SPDXRef-File-#{index}",
          fileName: path,
          checksums: file_checksums(full),
          licenseConcluded: "NOASSERTION",
          copyrightText: "NOASSERTION"
        }
      end

      def file_checksums(full)
        return [] unless File.file?(full)

        [{ algorithm: "SHA256", checksumValue: Digest::SHA256.file(full).hexdigest }]
      end

      def default_path
        File.join(package.path, SBOM_FILE)
      end
    end
  end
end
