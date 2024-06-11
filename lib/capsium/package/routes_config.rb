# frozen_string_literal: true

require "shale"

module Capsium
  class Package
    class RouteTarget < Shale::Mapper
      attribute :file, Shale::Type::String
      attribute :dataset, Shale::Type::String

      def fs_path(manifest)
        return unless file

        manifest.path_to_content_file(manifest.lookup(file)&.file)
      end

      def mime(manifest)
        manifest.lookup(file)&.mime
      end

      def validate(manifest, storage)
        if file
          target_path = fs_path(manifest)
          unless target_path && File.exist?(target_path) && target_path.to_s.start_with?(manifest.content_path.to_s)
            raise "Route target does not exist or is outside of the content directory: #{target_path}"
          end
        elsif dataset
          unless storage.datasets.any? { |ds| ds.config.name == dataset }
            raise "Dataset target does not exist: #{dataset}"
          end
        else
          raise "Route target must have either a file or a dataset"
        end
      end
    end

    class Route < Shale::Mapper
      attribute :path, Shale::Type::String
      attribute :target, RouteTarget
    end

    class RoutesConfig < Shale::Mapper
      attribute :routes, Route, collection: true

      def resolve(route)
        routes.detect { |r| r.path == route }
      end

      def add(route, target)
        target = RouteTarget.new(file: target) if target.is_a?(String)
        @routes ||= []
        @routes << Route.new(path: route, target: target)
      end

      def update(route, updated_route, updated_target)
        r = resolve(route)
        r.path = updated_route
        r.target = updated_target
        r
      end

      def remove(route)
        r = resolve(route)
        @routes.delete(r)
      end

      def sort!
        @routes.sort_by!(&:path)
        self
      end
    end
  end
end
