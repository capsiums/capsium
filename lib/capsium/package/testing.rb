# frozen_string_literal: true

module Capsium
  class Package
    # Runner for the Capsium package testing YAML DSL (05x-testing): a
    # package declares tests in tests/*.yaml files (top-level "tests"
    # list) of four kinds — route, file, data_validation and config —
    # and the suite runner executes them against the package.
    module Testing
      autoload :ConfigTest, "capsium/package/testing/config_test"
      autoload :Context, "capsium/package/testing/context"
      autoload :DataValidationTest, "capsium/package/testing/data_validation_test"
      autoload :FileTest, "capsium/package/testing/file_test"
      autoload :Report, "capsium/package/testing/report"
      autoload :RouteTest, "capsium/package/testing/route_test"
      autoload :TestCase, "capsium/package/testing/test_case"
      autoload :TestSuite, "capsium/package/testing/test_suite"
    end
  end
end
