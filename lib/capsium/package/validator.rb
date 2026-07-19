# frozen_string_literal: true

require "json"
require "marcel"
require "pathname"
require "tmpdir"

module Capsium
  class Package
    # Validates a package directory or .cap file against the canonical
    # schemas (ARCHITECTURE.md sections 2-6) and reports one result per
    # check. Used by `capsium package validate`.
    class Validator
      CheckResult = Data.define(:name, :ok, :messages) do
        def ok?
          ok
        end
      end

      EXTERNAL_REFERENCE_PATTERN = %r{(?:src|href)\s*=\s*["']https?://}in
      TEXT_CONTENT_MIME = %r{\Atext/|application/(json|javascript|xml)|image/svg\+xml}

      def initialize(package_path)
        @given_path = package_path
      end

      def run
        Dir.mktmpdir do |dir|
          @package_path = prepare(dir)
          [metadata_check, manifest_check, routes_check,
           storage_check, security_check, content_check]
        end
      end

      def valid?
        run.all?(&:ok?)
      end

      private

      def prepare(dir)
        return @given_path if File.directory?(@given_path)

        destination = File.join(dir, "package")
        Packager.new.unpack(@given_path, destination)
        destination
      end

      def metadata_check
        path = metadata_path(METADATA_FILE)
        return failure("metadata", ["metadata.json is missing"]) unless File.exist?(path)

        result("metadata", Metadata.new(path).config.format_errors)
      rescue StandardError => e
        failure("metadata", ["metadata.json is not valid: #{e.message}"])
      end

      def manifest_check
        manifest = Manifest.new(metadata_path(MANIFEST_FILE))
        missing = manifest.resources.keys.reject do |path|
          File.file?(File.join(@package_path, path))
        end
        result("manifest", missing.map { |path| "resource missing on disk: #{path}" })
      rescue StandardError => e
        failure("manifest", ["manifest.json is not valid: #{e.message}"])
      end

      def routes_check
        manifest = Manifest.new(metadata_path(MANIFEST_FILE))
        storage = Storage.new(metadata_path(STORAGE_FILE))
        routes = Routes.new(metadata_path(ROUTES_FILE), manifest, storage)
        problems = route_problems(routes, storage) + index_problems(routes)
        result("routes", problems)
      rescue StandardError => e
        failure("routes", ["routes.json is not valid: #{e.message}"])
      end

      def route_problems(routes, storage)
        routes.config.routes.flat_map do |route|
          route_target_problems(route, storage)
        end
      end

      def route_target_problems(route, storage)
        problems = []
        if route.dataset_route? && !route.path.start_with?(Route::DATASET_PATH_PREFIX)
          problems << "dataset route #{route.path} not under #{Route::DATASET_PATH_PREFIX}"
        end
        route.validate_target(@package_path, storage)
        problems
      rescue Error => e
        problems + [e.message]
      end

      def index_problems(routes)
        index = routes.config.index
        return ["index route is missing"] if index.nil?
        unless File.file?(File.join(@package_path, index))
          return ["index missing on disk: #{index}"]
        end
        return [] if File.extname(index).downcase == ".html"

        ["index is not an HTML file: #{index}"]
      end

      def storage_check
        storage = Storage.new(metadata_path(STORAGE_FILE))
        problems = storage.datasets.flat_map(&:validation_errors)
        result("storage", problems)
      rescue StandardError => e
        failure("storage", ["storage.json is not valid: #{e.message}"])
      end

      def security_check
        security = Security.new(metadata_path(SECURITY_FILE))
        return result("security", []) unless security.present?

        result("security", security.verify(@package_path).map(&:message))
      end

      def content_check
        offenders = Dir.glob(File.join(@package_path, CONTENT_DIR, "**", "*")).select do |file|
          File.file?(file) && text_file?(file) &&
            File.binread(file).match?(EXTERNAL_REFERENCE_PATTERN)
        end
        result("content", offenders.map do |file|
          "external reference in #{file.delete_prefix("#{@package_path}/")}"
        end)
      end

      def text_file?(path)
        mime = Marcel::MimeType.for(Pathname.new(path), name: File.basename(path))
        mime.match?(TEXT_CONTENT_MIME)
      end

      def metadata_path(file_name)
        File.join(@package_path, file_name)
      end

      def result(name, problems)
        CheckResult.new(name: name, ok: problems.empty?, messages: problems)
      end

      def failure(name, messages)
        CheckResult.new(name: name, ok: false, messages: messages)
      end
    end
  end
end
