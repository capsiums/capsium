# frozen_string_literal: true

module Capsium
  class Cli < Thor
    # Output formatting helpers for CLI subcommands.
    module Formatting
      private

      def format_result(result)
        line = "#{result.ok? ? 'PASS' : 'FAIL'} #{result.name}"
        return line if result.messages.empty?

        "#{line}: #{result.messages.join('; ')}"
      end

      # The resolved dependency tree (ARCHITECTURE.md section 4a): one
      # line per dependency showing the declared GUID and range, the
      # resolved version and the store .cap it resolved to, nested.
      def print_dependency_tree(package, indent = "")
        package.resolved_dependencies.each do |dep|
          puts "#{indent}- #{dep.guid} (#{dep.range}) => #{dep.version} [#{dep.path}]"
          print_dependency_tree(dep.package, "#{indent}  ")
        end
      end
    end
  end
end
