# frozen_string_literal: true

require "json"

module Capsium
  class Reactor
    # Serving of the reactor-level endpoints (introspection reports,
    # per-package save/versions/rollback), mixed into Reactor.
    module Endpoints
      include Responses

      private

      def serve_introspection(request, response)
        unless request.request_method == "GET"
          return respond_method_not_allowed(response,
                                            allow: "GET")
        end

        report = @introspection.report_for(request.path, params: request.query)
        return respond_not_found(response) if report.nil?

        respond_json(response, 200, report)
      end

      # POST /package/<name>/save: folds the mounted package's base plus
      # its overlay into a new versioned .cap in the workdir. Records
      # the saved version in the per-package version history.
      def serve_package_save(request, response)
        unless request.request_method == "POST"
          return respond_method_not_allowed(response,
                                            allow: "POST")
        end

        name = PACKAGE_SAVE_PATTERN.match(request.path)[:name]
        mount = mount_named(name)
        return respond_not_found(response) unless mount
        return respond_error(response, 403, "package #{name} is read-only") unless mount.writable?

        result = PackageSaver.new(mount).save(@workdir)
        record = version_history_for(name).record(
          version: result["version"],
          sha256: result["sha256"],
          path: result["path"]
        )
        result["saved_at"] = record.saved_at
        respond_json(response, 200, result)
      end

      # GET /package/<name>/versions: lists every recorded version,
      # oldest first.
      def serve_package_versions(request, response)
        unless request.request_method == "GET"
          return respond_method_not_allowed(response,
                                            allow: "GET")
        end

        name = PACKAGE_VERSIONS_PATTERN.match(request.path)[:name]
        return respond_not_found(response) unless mount_named(name)

        respond_json(response, 200, version_history_for(name).all.map(&:to_h))
      end

      # POST /package/<name>/rollback?to=<version-or-sha>: swaps the
      # mount's source .cap to the named version and reloads it. The
      # overlay is preserved (rollback restores content; the writable
      # overlay stays attached so subsequent writes still work).
      def serve_package_rollback(request, response)
        unless request.request_method == "POST"
          return respond_method_not_allowed(response,
                                            allow: "POST")
        end

        name = PACKAGE_ROLLBACK_PATTERN.match(request.path)[:name]
        mount = mount_named(name)
        return respond_not_found(response) unless mount

        target_version = request.query&.fetch("to", nil)
        return respond_error(response, 400, "missing 'to' query parameter") unless target_version

        record = version_history_for(name).find(target_version)
        return respond_error(response, 404, "no version matching #{target_version}") unless record

        mount.swap_source(record.path)
        respond_json(response, 200, { "name" => name, "rolled_back_to" => record.to_h })
      end

      def mount_named(name)
        @mounts.find { |candidate| candidate.package.name == name }
      end

      def version_history_for(name)
        VersionHistory.new(dir: @workdir, package_name: name)
      end
    end
  end
end
