# frozen_string_literal: true

require "json"
require "yaml"

module Capsium
  class Package
    module Testing
      # A "config" test (05x-testing): the configuration file must exist
      # in the package and parse as the declared format (json or yaml).
      # The known Capsium package configs (metadata.json, manifest.json,
      # routes.json, storage.json, security.json) are additionally
      # validated against their canonical models.
      class ConfigTest < TestCase
        FORMATS = %w[json yaml].freeze

        attr_reader :format, :config_file

        def initialize(name:, format:, config_file:)
          super(name: name)
          @format = format
          @config_file = config_file
        end

        def run(context)
          problems = config_problems(context)
          Result.new(name: name, ok: problems.empty?, messages: problems)
        end

        private

        def config_problems(context)
          return ["unsupported config format: #{format}"] unless FORMATS.include?(format)

          full_path = File.join(context.package_path, config_file.delete_prefix("/"))
          return ["config file missing in package: #{config_file}"] unless File.file?(full_path)

          parse(full_path)
          model_problems(full_path)
        rescue JSON::ParserError, Psych::SyntaxError => e
          ["cannot parse #{config_file}: #{e.message}"]
        end

        def parse(full_path)
          format == "yaml" ? YAML.load_file(full_path) : JSON.parse(File.read(full_path))
        end

        def model_problems(full_path)
          case File.basename(config_file)
          when Package::METADATA_FILE then Metadata.new(full_path).config.format_errors
          when Package::MANIFEST_FILE then probe { ManifestConfig.from_json(File.read(full_path)) }
          when Package::ROUTES_FILE then probe { RoutesConfig.from_json(File.read(full_path)) }
          when Package::STORAGE_FILE then probe { StorageConfig.from_json(File.read(full_path)) }
          when Package::SECURITY_FILE then probe { SecurityConfig.from_json(File.read(full_path)) }
          else []
          end
        end

        def probe
          yield
          []
        rescue StandardError => e
          [e.message]
        end
      end

      TestCase.register("config", ConfigTest)
    end
  end
end
