# frozen_string_literal: true

require "json"

module Capsium
  class Reactor
    # Serving of the reactor-level endpoints (introspection reports,
    # per-package save), mixed into Reactor.
    module Endpoints
      include Responses

      private

      def serve_introspection(request, response)
        return respond_method_not_allowed(response) unless request.request_method == "GET"

        report = @introspection.report_for(request.path, params: request.query)
        return respond_not_found(response) if report.nil?

        respond_json(response, 200, report)
      end

      # POST /package/<name>/save: folds the mounted package's base plus
      # its overlay into a new versioned .cap in the workdir.
      def serve_package_save(request, response)
        return respond_method_not_allowed(response) unless request.request_method == "POST"

        name = PACKAGE_SAVE_PATTERN.match(request.path)[:name]
        mount = @mounts.find { |candidate| candidate.package.name == name }
        return respond_not_found(response) unless mount
        return respond_error(response, 403, "package #{name} is read-only") unless mount.writable?

        respond_json(response, 200, PackageSaver.new(mount).save(@workdir))
      end
    end
  end
end
