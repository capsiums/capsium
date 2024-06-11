require "shale"

module Capsium
  class Package
    class Dependency < Shale::Mapper
      attribute :name, Shale::Type::String
      attribute :version, Shale::Type::String
    end

    class MetadataData < Shale::Mapper
      attribute :name, Shale::Type::String
      attribute :version, Shale::Type::String
      attribute :description, Shale::Type::String # Add description attribute
      attribute :dependencies, Dependency, collection: true
    end
  end
end
