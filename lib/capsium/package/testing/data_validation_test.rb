# frozen_string_literal: true

require "json"
require "json-schema"
require "yaml"

module Capsium
  class Package
    module Testing
      # A "data_validation" test (05x-testing): the rows of the data
      # file (format: json or yaml) must validate against the JSON
      # schema file. Array data validates row by row; a single document
      # validates as one row.
      class DataValidationTest < TestCase
        FORMATS = %w[json yaml].freeze

        attr_reader :format, :data_file, :schema_file

        def initialize(name:, format:, data_file:, schema_file:)
          super(name: name)
          @format = format
          @data_file = data_file
          @schema_file = schema_file
        end

        def run(context)
          problems = validation_problems(context)
          Result.new(name: name, ok: problems.empty?, messages: problems)
        end

        private

        def validation_problems(context)
          return ["unsupported data format: #{format}"] unless FORMATS.include?(format)

          schema = load_structured(context, schema_file)
          rows = load_structured(context, data_file)
          rows = [rows] unless rows.is_a?(Array)
          rows.each_with_index.flat_map { |row, index| row_problems(schema, row, index) }
        rescue Errno::ENOENT, JSON::ParserError, Psych::SyntaxError => e
          ["cannot load data or schema: #{e.message}"]
        end

        def load_structured(context, relative_path)
          full_path = File.join(context.package_path, relative_path.delete_prefix("/"))
          if File.extname(full_path).match?(/\A\.ya?ml\z/i)
            YAML.load_file(full_path)
          else
            JSON.parse(File.read(full_path))
          end
        end

        def row_problems(schema, row, index)
          JSON::Validator.fully_validate(schema, row).map do |message|
            "row #{index}: #{message}"
          end
        end
      end

      TestCase.register("data_validation", DataValidationTest)
    end
  end
end
