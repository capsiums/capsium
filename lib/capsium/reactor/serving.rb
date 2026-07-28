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

      # One request metric and one log line per served request.
      def record_request(request, response)
        status = response.status
        return if status.nil?

        @metrics.record(status)
        @log_buffer.add("#{request.request_method} #{request.path} -> #{status}")
      end

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
        if GraphqlApi.path?(inner) && mount.graphql?
          return mount.graphql_api.handle(request, response)
        end
        if ContentApi.write_method?(request.request_method)
          return serve_content_api(mount, identity, inner, request, response)
        end
        return respond_method_not_allowed(response) unless %w[GET
                                                              HEAD].include?(request.request_method)

        route = mount.routes.resolve(inner)
        return respond_not_found(response) unless route
        return unless authorized?(identity, route, response)

        serve_route(mount, route, request, response)
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

      def serve_route(mount, route, request, response)
        case route.kind
        when :dataset then serve_dataset(mount, route.dataset, response)
        when :resource then serve_file(mount, route, request, response)
        else respond_not_implemented(response)
        end
      end

      def serve_file(mount, route, request, response)
        # Streaming mode: read directly from the .cap zip without
        # going through the merged view filesystem path.
        if @streaming && mount.package.zip_source_path
          return serve_file_streaming(mount, route, request, response)
        end

        content_path = mount.merged_view.resolve(route.resource)
        return respond_not_found(response) unless content_path

        brotli_path = brotli_sidecar_for(content_path, request)
        if brotli_path
          response.status = 200
          response["Content-Type"] = content_type_for(mount, route, content_path)
          response["Content-Encoding"] = "br"
          response["Vary"] = vary_header(request, "Accept-Encoding")
          response.body = File.binread(brotli_path)
          return
        end

        body, headers = inherited_processing(route, File.read(content_path),
                                             headers_for(route))
        response.status = 200
        response["Content-Type"] = content_type_for(mount, route, content_path)
        headers.each { |name, value| response[name] = value }
        response.body = body
      end

      def serve_file_streaming(mount, route, _request, response)
        require "zip"
        resource = route.resource
        Zip::File.open(mount.package.zip_source_path) do |zip_file|
          entry = zip_file.find_entry(resource)
          return respond_not_found(response) unless entry

          body = entry.get_input_stream.read
          body, headers = inherited_processing(route, body, headers_for(route))
          response.status = 200
          response["Content-Type"] = content_type_for(mount, route, resource)
          headers.each { |name, value| response[name] = value }
          response.body = body
        end
      end

      # Returns the path to a brotli-precompressed sidecar when the
      # client accepts br encoding AND a <file>.br sidecar exists on
      # disk alongside the resolved resource. Otherwise nil — the
      # caller serves the original file uncompressed.
      def brotli_sidecar_for(content_path, request)
        accept = request["Accept-Encoding"].to_s
        return nil unless accept.split(",").map(&:strip).any?("br")

        sidecar = "#{content_path}.br"
        File.file?(sidecar) ? sidecar : nil
      end

      def vary_header(request, value)
        existing = request["Vary"].to_s
        existing.empty? ? value : "#{existing}, #{value}"
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
