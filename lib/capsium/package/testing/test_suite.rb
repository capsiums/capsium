# frozen_string_literal: true

require "timeout"
require "yaml"

module Capsium
  class Package
    module Testing
      # Loads and runs the package's tests/*.yaml suites (05x-testing).
      # Route tests are served by a reactor on an ephemeral port for the
      # duration of the run. Invalid test definitions are reported as
      # failed results instead of aborting the run.
      class TestSuite
        TESTS_DIR = "tests"

        # Referencing the built-in test kinds triggers their autoload,
        # which registers them in TestCase.types (each kind file
        # self-registers on load).
        BUILTIN_TEST_KINDS = [RouteTest, FileTest, DataValidationTest, ConfigTest].freeze

        attr_reader :package

        def initialize(package)
          @package = package
        end

        def test_files
          Dir.glob(File.join(@package.path, TESTS_DIR, "*.{yaml,yml}"))
        end

        def run
          report = Report.new
          loaded = load_cases(report)
          with_reactor(loaded) do |base_url|
            context = Context.new(package_path: @package.path, base_url: base_url)
            loaded.each { |test_case| report << run_case(test_case, context) }
          end
          report
        end

        private

        def load_cases(report)
          test_files.flat_map do |file|
            definitions = YAML.load_file(file)
            tests = definitions.is_a?(Hash) ? definitions["tests"] : nil
            Array(tests).map { |definition| TestCase.build(definition) }
          rescue Psych::SyntaxError, TestCase::DefinitionError => e
            report << TestCase::Result.new(name: File.basename(file), ok: false,
                                           messages: [e.message])
            []
          end
        end

        def run_case(test_case, context)
          test_case.run(context)
        rescue StandardError => e
          TestCase::Result.new(name: test_case.name, ok: false,
                               messages: ["#{e.class}: #{e.message}"])
        end

        def with_reactor(loaded)
          return yield nil unless loaded.any?(RouteTest)

          reactor = Capsium::Reactor.new(package: @package, port: 0)
          server_thread = Thread.new { reactor.server.start }
          # WEBrick race: shutdown before start reaches :Running would
          # leave the server running forever.
          wait_until_running(reactor.server)
          yield "http://127.0.0.1:#{reactor.server.listeners.first.addr[1]}"
        ensure
          shutdown_reactor(reactor, server_thread) if reactor
        end

        def wait_until_running(server)
          Timeout.timeout(5) { sleep 0.01 until server.status == :Running }
        end

        def shutdown_reactor(reactor, server_thread)
          reactor.server.shutdown
          server_thread.join
        end
      end
    end
  end
end
