require "shale"

module Capsium
  class Package
    class StorageConfig < Shale::Mapper
      attribute :datasets, DatasetConfig, collection: true
    end
  end
end
