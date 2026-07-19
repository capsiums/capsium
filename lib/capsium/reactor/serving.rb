# frozen_string_literal: true

require "marcel"
require "pathname"

module Capsium
  class Reactor
    # Serving of resolved routes (static files through the merged view,
    # datasets, handler-route 501s), mixed into Reactor. Includes route
    # inheritance processing per 05x-routing.
    module Serving
      include Responses

      private

      # The mount answering a request path: longest matching prefix wins.
      def resolve_mount(path)
        mounts_by_length.find { |mount| mount.matches?(path) }
      end

      def mounts_by_length
        @mounts_by_length ||= @mounts.sort_by { |mount| -mount.path.length }
      end

      # The root ("/") mount, or the first mount when nothing is mounted
      # at the root: its package drives the single-package readers
      # (package, routes, merged_view), authentication and the
      # reactor-level introspection.
      def root_mount
        @mounts.find { |mount| mount.path == Mount::ROOT_PATH } || @mounts.first
      end

      # Serves a request that matched a mount: dataset CRUD and content
      # writes go to the mount's APIs, everything else resolves against
      # the mount's routes. Route-level access control is enforced for
      # the addressed route in every case.
      def serve_mounted_request(mount, identity, request, response)
        inner = mount.inner_path(request.path)
        return serve_data_api(mount, identity, inner, request, response) if DataApi.path?(inner)
        if ContentApi.write_method?(request.request_method)
          return serve_content_api(mount, identity, inner, request, response)
        end

        route = mount.routes.resolve(inner)
        return respond_not_found(response) unless route
        return unless authorized?(identity, route, response)

        serve_route(mount, route, response)
      end

      def serve_data_api(mount, identity, inner, request, response)
        route = mount.data_api.route_for(inner)
        return respond_not_found(response) unless route
        return unless authorized?(identity, route, response)

        mount.data_api.handle(inner, request, response)
      end

      def serve_content_api(mount, identity, inner, request, response)
        route = mount.routes.resolve(inner)
        return unless !route || authorized?(identity, route, response)

        mount.content_api.handle(inner, request, response)
      end

      # Route-level access control (05x-authentication): writes the
      # challenge/forbidden response and returns false when the
      # identity may not proceed.
      def authorized?(identity, route, response)
        case @authenticator.authorize(identity, route.access_control)
        when :unauthenticated
          @authenticator.challenge(response)
          false
        when :forbidden
          respond_forbidden(response)
          false
        else true
        end
      end

      def serve_route(mount, route, response)
        case route.kind
        when :dataset then serve_dataset(mount, route.dataset, response)
        when :resource then serve_file(mount, route, response)
        else respond_not_implemented(response)
        end
      end

      def serve_file(mount, route, response)
        content_path = mount.merged_view.resolve(route.resource)
        return respond_not_found(response) unless content_path

        body, headers = inherited_processing(route, File.read(content_path),
                                             headers_for(route))
        response.status = 200
        response["Content-Type"] = content_type_for(mount, route, content_path)
        headers.each { |name, value| response[name] = value }
        response.body = body
      end

      # Route inheritance processing (05x-routing section "Route
      # Inheritance"): responseRewrite replaces the body and/or overrides
      # headers; responseHeaders are merged over the served headers.
      # requestHeaders are parsed and exposed on the route for forwarding
      # reactors; this reactor serves statically without an upstream, so
      # they do not alter its responses.
      def inherited_processing(route, body, headers)
        rewrite = route.response_rewrite
        if rewrite
          body = rewrite.body unless rewrite.body.nil?
          headers = headers.merge(rewrite.headers) if rewrite.headers
        end
        headers = headers.merge(route.response_headers) if route.response_headers
        [body, headers]
      end

      # The route's declared MIME type, detected from the resolved file
      # for resources the manifest does not list (dependency content
      # reached through inheritance, layer-only files).
      def content_type_for(mount, route, content_path)
        route.mime(mount.package.manifest) ||
          Marcel::MimeType.for(Pathname.new(content_path),
                               name: File.basename(content_path))
      end

      def headers_for(route)
        route.headers || (@cache_control ? { "Cache-Control" => @cache_control } : {})
      end

      def serve_dataset(mount, dataset_name, response)
        dataset = mount.package.storage.dataset(dataset_name)
        if dataset
          response.status = 200
          response["Content-Type"] = "application/json"
          response.body = JSON.generate(mount.dataset_data(dataset))
        else
          respond_not_found(response)
        end
      end
    end
  end
end
