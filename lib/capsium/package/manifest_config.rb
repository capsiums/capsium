# frozen_string_literal: true

require "json"
require "lutaml/model"

module Capsium
  class Package
    # A single manifest resource entry (ARCHITECTURE.md section 3).
    class Resource < Lutaml::Model::Serializable
      VISIBILITIES = %w[exported private].freeze

      attribute :type, :string
      attribute :visibility, :string, values: VISIBILITIES, default: "exported"
      attribute :version, :string

      json do
        map :type, to: :type
        map :visibility, to: :visibility
        map :version, to: :version
      end
    end

    # Canonical manifest.json model: an object keyed by package-relative
    # resource path. The legacy gem form ({"content": [{file, mime}]}) is
    # accepted on read and normalized; writers emit only the object form.
    class ManifestConfig < Lutaml::Model::Serializable
      attribute :resources, :hash, default: {}

      json do
        map :resources, with: { from: :resources_from_json, to: :resources_to_json }
      end

      def self.from_json(json)
        doc = JSON.parse(json)
        doc["resources"] ||= legacy_resources(doc.delete("content")) if doc.key?("content")
        super(JSON.generate(doc))
      end

      def self.legacy_resources(content)
        (content || []).to_h do |item|
          [item["file"], { "type" => item["mime"], "visibility" => "exported" }]
        end
      end
      private_class_method :legacy_resources

      def resources_from_json(model, value)
        model.resources = (value || {}).to_h do |path, attributes|
          [path, Resource.from_json(JSON.generate(attributes))]
        end
      end

      def resources_to_json(model, doc)
        doc["resources"] = model.resources.sort.to_h do |path, resource|
          [path, JSON.parse(resource.to_json)]
        end
      end

      def sort!
        self.resources = resources.sort.to_h
        self
      end
    end
  end
end
