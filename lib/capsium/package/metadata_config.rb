# frozen_string_literal: true

require "json"
require "lutaml/model"
require "uri"

module Capsium
  class Package
    class Repository < Lutaml::Model::Serializable
      attribute :type, :string
      attribute :url, :string

      json do
        map :type, to: :type
        map :url, to: :url
      end
    end

    # Canonical metadata.json model (ARCHITECTURE.md section 2).
    #
    # The legacy gem form of "dependencies" (an array of {name, version}
    # objects) is accepted on read and normalized to the canonical object
    # form; writers emit only the object form.
    class MetadataData < Lutaml::Model::Serializable
      KEBAB_CASE_PATTERN = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
      SEMVER_PATTERN = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      attribute :name, :string
      attribute :version, :string
      attribute :description, :string
      attribute :guid, :string
      attribute :uuid, :string
      attribute :author, :string
      attribute :license, :string
      attribute :repository, Repository
      attribute :dependencies, :hash, default: {}
      attribute :read_only, :boolean

      json do
        map :name, to: :name
        map :version, to: :version
        map :description, to: :description
        map :guid, to: :guid
        map :uuid, to: :uuid
        map :author, to: :author
        map :license, to: :license
        map :repository, to: :repository
        map :dependencies, to: :dependencies
        map "readOnly", to: :read_only
      end

      def self.from_json(json)
        doc = JSON.parse(json)
        doc["dependencies"] = normalize_dependencies(doc["dependencies"])
        super(JSON.generate(doc))
      end

      def self.normalize_dependencies(dependencies)
        return {} if dependencies.nil?
        return dependencies unless dependencies.is_a?(Array)

        dependencies.to_h { |dep| [dep["name"], dep["version"]] }
      end
      private_class_method :normalize_dependencies

      # Field-level format validations (ARCHITECTURE.md section 2).
      # Returns a list of human-readable problems; empty when valid.
      def format_errors
        presence_errors + format_field_errors
      end

      private

      def presence_errors
        problems = []
        problems << "name is missing" if name.to_s.empty?
        problems << "version is missing" if version.to_s.empty?
        problems << "description is missing" if description.to_s.empty?
        problems << "guid is missing" if guid.to_s.empty?
        problems << "uuid is missing" if uuid.to_s.empty?
        problems
      end

      def format_field_errors
        problems = []
        problems << "name must be kebab-case" if invalid?(name, KEBAB_CASE_PATTERN)
        problems << "version must be semver" if invalid?(version, SEMVER_PATTERN)
        problems << "guid must be a URI" if guid && !uri?(guid)
        problems << "uuid is not a valid UUID" if invalid?(uuid, UUID_PATTERN)
        problems
      end

      def invalid?(value, pattern)
        !value.nil? && !value.match?(pattern)
      end

      def uri?(value)
        URI.parse(value).is_a?(URI::Generic)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
