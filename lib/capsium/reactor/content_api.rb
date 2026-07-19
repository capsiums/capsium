# frozen_string_literal: true

require "json"

module Capsium
  class Reactor
    # Content writes over the mount's overlay (ARCHITECTURE.md section
    # 5a): PUT creates/overwrites a content file (creating its route on
    # demand), DELETE records a tombstone so the path 404s even when a
    # lower layer holds the file. The immutable package never changes
    # on disk. Text bodies only for v1.
    class ContentApi
      include Responses

      WRITE_METHODS = %w[PUT DELETE].freeze
      CONTENT_PREFIX = "#{Package::CONTENT_DIR}/".freeze

      def self.write_method?(method)
        WRITE_METHODS.include?(method)
      end

      def initialize(mount)
        @mount = mount
      end

      def handle(inner_path, request, response)
        return read_only(response) unless @mount.writable?

        route = @mount.routes.resolve(inner_path)
        return guard_route(route, inner_path, response) if route && !writable_route?(route)

        case request.request_method
        when "PUT" then put_content(inner_path, route, request, response)
        when "DELETE" then delete_content(inner_path, route, response)
        else respond_method_not_allowed(response)
        end
      end

      private

      # A route is writable when it is a plain resource route (or no
      # route at all): dataset paths are the DataApi's, handler routes
      # are not writable, dependency content stays immutable.
      def writable_route?(route)
        route.kind == :resource && !route.dependency_reference?
      end

      def guard_route(route, inner_path, response)
        return respond_method_not_allowed(response) if route.kind == :dataset

        respond_error(response, 400, "cannot write #{route.kind} content: #{inner_path}")
      end

      def put_content(inner_path, route, request, response)
        relative = content_relative(resource_path(inner_path, route))
        return unsafe_path(inner_path, response) if relative.nil?

        @mount.overlay.write_content(relative, request.body.to_s)
        resource = "#{Package::CONTENT_DIR}/#{relative}"
        @mount.package.routes.add_route(inner_path, resource) unless route
        respond_json(response, 200, { path: inner_path, resource: resource })
      rescue Overlay::Error => e
        respond_error(response, 400, e.message)
      end

      # Tombstones the served resource: 404 when the path is already
      # tombstoned or nothing (here or in a lower layer) serves it.
      def delete_content(inner_path, route, response)
        relative = content_relative(resource_path(inner_path, route))
        return unsafe_path(inner_path, response) if relative.nil?
        return respond_not_found(response) if @mount.overlay.tombstones.include?(relative)
        unless @mount.merged_view.resolve("#{Package::CONTENT_DIR}/#{relative}")
          return respond_not_found(response)
        end

        @mount.overlay.delete_content(relative)
        response.status = 204
      rescue Overlay::Error => e
        respond_error(response, 400, e.message)
      end

      def unsafe_path(inner_path, response)
        respond_error(response, 400, "unsafe content path: #{inner_path}")
      end

      def read_only(response)
        respond_error(response, 403, "package #{@mount.package.name} is read-only")
      end

      # The package resource a write addresses: the existing route's
      # resource (overwrite what GET serves), else a content file
      # derived from the URL path (created on demand).
      def resource_path(inner_path, route)
        route ? route.resource : "#{Package::CONTENT_DIR}/#{inner_path.delete_prefix('/')}"
      end

      # The content/-relative path for a package resource, nil for
      # unsafe paths (outside content/, dot segments).
      def content_relative(resource_path)
        return nil unless resource_path.start_with?(CONTENT_PREFIX)

        relative = resource_path.delete_prefix(CONTENT_PREFIX)
        segments = relative.split("/")
        return nil if segments.empty? || segments.any? { |s| s.empty? || s == ".." }

        relative
      end
    end
  end
end
