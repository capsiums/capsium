# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium::Package::Testing do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }

  def write_files(root, files)
    files.each do |relative, content|
      path = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def run_suite(dir, tests_yaml, extra_files = {})
    write_files(dir, {
      "metadata.json" => '{"name": "spec-package", "version": "0.1.0"}',
      "content/index.html" => "<h1>Hello</h1>",
      "tests/suite.yaml" => tests_yaml
    }.merge(extra_files))
    Capsium::Package::Testing::TestSuite.new(Capsium::Package.new(dir)).run
  end

  describe Capsium::Package::Testing::TestSuite do
    it "runs the fixture package suite to full success" do
      package = Capsium::Package.new(File.join(fixtures_path, "test-package"))
      report = described_class.new(package).run

      expect(report.ok?).to be(true)
      expect(report.summary).to eq("7 tests, 0 failures")
      expect(report.results.map(&:name)).to contain_exactly(
        "Home route responds", "Index route responds with HTML",
        "Missing route is a 404", "Content file exists", "Metadata exists",
        "Animals data validates against its schema", "Metadata config is well-formed"
      )
    end

    it "is empty and ok for a package without tests" do
      Dir.mktmpdir do |dir|
        write_files(dir, { "metadata.json" => "{}" })
        report = described_class.new(Capsium::Package.new(dir)).run
        expect(report.results).to be_empty
        expect(report.ok?).to be(true)
      end
    end

    it "reports invalid YAML files as failed results" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, "tests: [unclosed")
        expect(report.ok?).to be(false)
        expect(report.failures.first.name).to eq("suite.yaml")
      end
    end

    it "reports unknown test types as failed results" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, "tests:\n  - name: Mystery\n    type: mystery\n")
        expect(report.ok?).to be(false)
        expect(report.failures.first.messages.first).to match(/unknown test type: mystery/)
      end
    end

    it "reports malformed test definitions as failed results" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, "tests:\n  - just-a-string\n")
        expect(report.ok?).to be(false)
        expect(report.failures.first.messages.first).to match(/not a mapping/)
      end
    end
  end

  describe Capsium::Package::Testing::RouteTest do
    it "fails on status mismatch" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML)
          tests:
            - name: Gone
              type: route
              url: "/gone"
              expected_status: 200
        YAML
        expect(report.failures.first.messages.first).to eq("expected status 200, got 404")
      end
    end

    it "fails when the response body lacks the expected string" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML)
          tests:
            - name: Body
              type: route
              url: "/"
              expected_status: 200
              response_contains: "Goodbye"
        YAML
        expect(report.failures.first.messages.first).to match(/does not contain "Goodbye"/)
      end
    end

    it "reports unexpected errors as failed results" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML)
          tests:
            - name: Bad URL
              type: route
              url: "http://["
              expected_status: 200
        YAML
        expect(report.failures.first.messages.first).to match(/URI::InvalidURIError/)
      end
    end
  end

  describe Capsium::Package::Testing::FileTest do
    it "fails for a missing file" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML)
          tests:
            - name: Missing
              type: file
              path: "content/missing.txt"
        YAML
        expect(report.failures.first.messages.first)
          .to eq("file missing in package: content/missing.txt")
      end
    end

    it "fails when the content check does not match" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML)
          tests:
            - name: Content
              type: file
              path: "content/index.html"
              contains: "Goodbye"
        YAML
        expect(report.failures.first.messages.first).to match(/does not contain "Goodbye"/)
      end
    end
  end

  describe Capsium::Package::Testing::DataValidationTest do
    it "fails with the offending row when a row does not validate" do
      Dir.mktmpdir do |dir|
        extra = { "data/bad.json" => '[{"name": "cat"}]',
                  "data/schema.json" => '{"required": ["name", "legs"]}' }
        report = run_suite(dir, <<~YAML, extra)
          tests:
            - name: Data
              type: data_validation
              format: json
              data_file: "data/bad.json"
              schema_file: "data/schema.json"
        YAML
        expect(report.failures.first.messages.first).to match(/row 0: /)
      end
    end

    it "validates YAML data against a YAML schema" do
      Dir.mktmpdir do |dir|
        extra = { "data/ok.yaml" => "- name: cat\n  legs: 4\n",
                  "data/schema.yaml" => "type: object\nrequired: [name, legs]\n" }
        report = run_suite(dir, <<~YAML, extra)
          tests:
            - name: YAML Data
              type: data_validation
              format: yaml
              data_file: "data/ok.yaml"
              schema_file: "data/schema.yaml"
        YAML
        expect(report.ok?).to be(true)
      end
    end

    it "fails for a missing data file and an unsupported format" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML)
          tests:
            - name: Missing data
              type: data_validation
              format: json
              data_file: "data/missing.json"
              schema_file: "data/schema.json"
            - name: CSV data
              type: data_validation
              format: csv
              data_file: "data/x.csv"
              schema_file: "data/schema.json"
        YAML
        messages = report.failures.flat_map(&:messages)
        expect(messages).to include(match(/cannot load data or schema/),
                                    match(/unsupported data format: csv/))
      end
    end
  end

  describe Capsium::Package::Testing::ConfigTest do
    it "fails for a malformed known config via its canonical model" do
      Dir.mktmpdir do |dir|
        extra = { "metadata.json" => '{"name": "INVALID NAME", "version": "0.1.0"}' }
        report = run_suite(dir, <<~YAML, extra)
          tests:
            - name: Metadata
              type: config
              format: json
              config_file: "metadata.json"
        YAML
        expect(report.failures.first.messages).to include(match(/name must be kebab-case/))
      end
    end

    it "passes for an arbitrary well-formed YAML file" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML, { "custom.yaml" => "key: value\n" })
          tests:
            - name: Custom YAML
              type: config
              format: yaml
              config_file: "custom.yaml"
        YAML
        expect(report.ok?).to be(true)
      end
    end

    it "fails for missing, unparsable and unsupported configs" do
      Dir.mktmpdir do |dir|
        report = run_suite(dir, <<~YAML, { "broken.json" => "{oops" })
          tests:
            - name: Missing config
              type: config
              format: json
              config_file: "missing.json"
            - name: Broken config
              type: config
              format: json
              config_file: "broken.json"
            - name: XML config
              type: config
              format: xml
              config_file: "broken.json"
        YAML
        messages = report.failures.flat_map(&:messages)
        expect(messages).to include(match(/config file missing/),
                                    match(/cannot parse broken\.json/),
                                    match(/unsupported config format: xml/))
      end
    end
  end

  describe Capsium::Package::Testing::TestCase do
    it "registers the four DSL test kinds" do
      expect(described_class.types.keys)
        .to contain_exactly("route", "file", "data_validation", "config")
    end

    it "rejects definitions without a type" do
      expect { described_class.build("name" => "x") }
        .to raise_error(described_class::DefinitionError, /has no type/)
    end

    it "rejects definitions with missing required attributes" do
      expect { described_class.build("name" => "x", "type" => "file") }
        .to raise_error(described_class::DefinitionError, /invalid file test/)
    end
  end
end
