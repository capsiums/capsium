# frozen_string_literal: true

require "lutaml/model"

module Capsium
  class Package
    class Repository < Lutaml::Model::Serializable
      attribute :type, :string
      attribute :url, :string

      json do
        map "type", to: :type
        map "url", to: :url
      end
    end

    class AccessMode < Lutaml::Model::Serializable
      attribute :read, :boolean, default: -> { true }
      attribute :write, :boolean, default: -> { false }
      attribute :execute, :boolean, default: -> { false }

      json do
        map "read", to: :read
        map "write", to: :write
        map "execute", to: :execute
      end
    end

    class Dependency < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :version, :string

      json do
        map "name", to: :name
        map "version", to: :version
      end
    end

    class MetadataData < Lutaml::Model::Serializable
      attribute :identifier, :string
      attribute :uuid, :string
      attribute :name, :string
      attribute :version, :string
      attribute :description, :string
      attribute :author, :string
      attribute :license, :string
      attribute :repository, Repository
      attribute :access_mode, AccessMode
      attribute :dependencies, Dependency, collection: true

      json do
        map "identifier", to: :identifier
        map "uuid", to: :uuid
        map "name", to: :name
        map "version", to: :version
        map "description", to: :description
        map "author", to: :author
        map "license", to: :license
        map "repository", to: :repository
        map "accessMode", to: :access_mode
        map "dependencies", to: :dependencies
      end
    end
  end
end
