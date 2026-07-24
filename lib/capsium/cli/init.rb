# frozen_string_literal: true

require "fileutils"
require "find"
require "json"
require "securerandom"

module Capsium
  class Cli
    # Scaffolds a new package from a built-in template. Templates live
    # under lib/capsium/cli/templates/<name>/ as plain directory trees
    # with two placeholder substitutions:
    #
    #   {{name}}   - the package name (sanitized to be a valid path
    #                component and JSON-safe identifier)
    #   {{uuid}}   - a fresh RFC 4122 UUID for the metadata guid
    #
    # Templates don't run any code; they're copied verbatim and the
    # placeholders are replaced textually. This keeps the template
    # surface auditable (no ERB, no code execution) and matches the
    # spec's "static source, deterministic output" principle.
    class Init
      TEMPLATES_DIR = File.expand_path("templates", __dir__)
      TEMPLATES = Dir.children(TEMPLATES_DIR).select do |entry|
        File.directory?(File.join(TEMPLATES_DIR, entry))
      end.freeze

      # Package names map to filesystem paths and JSON-string values
      # without further escaping. Restrict to a safe subset (letters,
      # digits, dash, underscore, dot) so the name round-trips cleanly
      # into both contexts.
      NAME_PATTERN = /\A[A-Za-z0-9._-]+\z/

      Result = Data.define(:name, :template, :path)

      def self.templates = TEMPLATES

      def self.call(template:, name:, parent_dir: Dir.pwd)
        new(template, name, parent_dir).call
      end

      def initialize(template, name, parent_dir)
        @template = template
        @name = name
        @parent_dir = parent_dir
      end

      def call
        validate_template!
        validate_name!
        target = resolve_target
        substitutions = { "name" => @name, "uuid" => SecureRandom.uuid }
        copy_template(target, substitutions)
        Result.new(name: @name, template: @template, path: target)
      end

      private

      def validate_template!
        return if TEMPLATES.include?(@template)

        raise ArgumentError,
              "unknown template #{@template.inspect}. " \
              "Available: #{TEMPLATES.join(', ')}"
      end

      def validate_name!
        return if @name.is_a?(String) && @name.match?(NAME_PATTERN)

        raise ArgumentError,
              "invalid name #{@name.inspect} " \
              "(allowed: letters, digits, '.', '_', '-')"
      end

      def resolve_target
        target = File.expand_path(@name, @parent_dir)
        return target unless File.exist?(target)

        raise ArgumentError,
              "target already exists: #{target} (move it aside or pick another name)"
      end

      def copy_template(target, substitutions)
        source = File.join(TEMPLATES_DIR, @template)
        FileUtils.cp_r(source, target)
        Find.find(target) do |path|
          next if File.directory?(path)

          apply_substitutions!(path, substitutions)
        end
      end

      def apply_substitutions!(path, substitutions)
        content = File.read(path)
        new_content = substitutions.reduce(content) do |acc, (key, value)|
          acc.gsub("{{#{key}}}", value.to_s)
        end
        File.write(path, new_content) if new_content != content
      end
    end
  end
end
