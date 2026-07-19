# frozen_string_literal: true

module Capsium
  class Package
    module Testing
      # A "file" test (05x-testing): the file must exist in the package;
      # optionally its content must contain a string.
      class FileTest < TestCase
        attr_reader :path, :contains

        def initialize(name:, path:, contains: nil)
          super(name: name)
          @path = path
          @contains = contains
        end

        def run(context)
          problems = existence_problems(context) + contains_problems(context)
          Result.new(name: name, ok: problems.empty?, messages: problems)
        end

        private

        def full_path(context)
          File.join(context.package_path, path.delete_prefix("/"))
        end

        def existence_problems(context)
          return [] if File.file?(full_path(context))

          ["file missing in package: #{path}"]
        end

        def contains_problems(context)
          return [] unless contains && File.file?(full_path(context))
          return [] if File.read(full_path(context)).include?(contains)

          ["file #{path} does not contain #{contains.inspect}"]
        end
      end

      TestCase.register("file", FileTest)
    end
  end
end
