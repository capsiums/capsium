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

      # Serves a request that matched a mount: resolves the
      # package-local path against the mount's routes, enforces
      # route-level access control and serves the route.
      def serve_mounted_request(mount, identity, request, response)
        route = mount.routes.resolve(mount.inner_path(request.path))
        return respond_not_found(response) unless route

        case @authenticator.authorize(identity, route.access_control)
        when :unauthenticated then return @authenticator.challenge(response)
        when :forbidden then return respond_forbidden(response)
        end

        serve_route(mount, route, response)
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
          response.body = JSON.generate(dataset.data)
        else
          respond_not_found(response)
        end
      end
    end
  end
end
