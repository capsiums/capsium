require "shale"

module Capsium
  class Package
    class ManifestConfigItem < Shale::Mapper
      attribute :file, Shale::Type::String
      attribute :mime, Shale::Type::String
    end

    class ManifestConfig < Shale::Mapper
      attribute :content, ManifestConfigItem, collection: true
    end
  end
end
