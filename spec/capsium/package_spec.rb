# frozen_string_literal: true

require "spec_helper"
require "capsium/package"
require_relative "package/package_spec_helper"

RSpec.describe Capsium::Package do
  context "with a bare package as directory" do
    let(:package_name) { "bare_package" }
    let(:package_version) { "0.1.0" }

    include_context "package setup", "bare_package", "0.1.0", :directory

    describe "loading and processing" do
      include_examples "a package loader",
        { name: "bare_package", version: "0.1.0", dependencies: [] },
        {
          content: [
            { file: "content/index.html", mime: "text/html" },
            { file: "content/example.css", mime: "text/css" },
            { file: "content/example.js", mime: "application/javascript" },
          ],
        },
        {
          routes: [
            { path: "/", target: { file: "content/index.html" } },
            { path: "/index", target: { file: "content/index.html" } },
            { path: "/index.html", target: { file: "content/index.html" } },
            { path: "/example.css", target: { file: "content/example.css" } },
            { path: "/example.js", target: { file: "content/example.js" } },
          ],
        }

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:directory)
      end
    end
  end

  context "with a data package as directory" do
    let(:package_name) { "data_package" }
    let(:package_version) { "0.1.0" }

    include_context "package setup", "data_package", "0.1.0", :directory

    describe "loading and processing" do
      include_examples "a package loader",
        { name: "data_package", version: "0.1.0", dependencies: [] },
        {
          content: [
            { file: "content/index.html", mime: "text/html" },
            { file: "content/example.css", mime: "text/css" },
            { file: "content/example.js", mime: "application/javascript" },
            { file: "data/animals.yaml", mime: "application/x-yaml" },
            { file: "data/animals_schema.yaml", mime: "application/x-yaml" },
          ],
        },
        {
          routes: [
            { path: "/", target: { file: "content/index.html" } },
            { path: "/index", target: { file: "content/index.html" } },
            { path: "/index.html", target: { file: "content/index.html" } },
            { path: "/example.css", target: { file: "content/example.css" } },
            { path: "/example.js", target: { file: "content/example.js" } },
            { path: "/api/v1/data/animals", target: { dataset: "animals" } },
          ],
        },
        {
          datasets: [
            {
              name: "animals",
              source: "data/animals.yaml",
              format: "yaml",
              schema: "data/animals_schema.yaml",
            },
          ],
        }

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:directory)
      end
    end
  end

  context "with a bare package as .cap file" do
    let(:package_name) { "bare_package" }
    let(:package_version) { "0.1.0" }

    include_context "package setup", "bare_package", "0.1.0", :cap_file

    describe "loading and processing" do
      include_examples "a package loader",
        { name: "bare_package", version: "0.1.0", dependencies: [] },
        {
          content: [
            { file: "content/index.html", mime: "text/html" },
            { file: "content/example.css", mime: "text/css" },
            { file: "content/example.js", mime: "application/javascript" },
          ],
        },
        {
          routes: [
            { path: "/", target: { file: "content/index.html" } },
            { path: "/index", target: { file: "content/index.html" } },
            { path: "/index.html", target: { file: "content/index.html" } },
            { path: "/example.css", target: { file: "content/example.css" } },
            { path: "/example.js", target: { file: "content/example.js" } },
          ],
        }

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:cap_file)
      end
    end
  end

  context "with a data package as .cap file" do
    let(:package_name) { "data_package" }
    let(:package_version) { "0.1.0" }

    include_context "package setup", "data_package", "0.1.0", :cap_file

    describe "loading and processing" do
      include_examples "a package loader",
        { name: "data_package", version: "0.1.0", dependencies: [] },
        {
          content: [
            { file: "content/index.html", mime: "text/html" },
            { file: "content/example.css", mime: "text/css" },
            { file: "content/example.js", mime: "application/javascript" },
            { file: "data/animals.yaml", mime: "application/x-yaml" },
            { file: "data/animals_schema.yaml", mime: "application/x-yaml" },
          ],
        },
        {
          routes: [
            { path: "/", target: { file: "content/index.html" } },
            { path: "/index", target: { file: "content/index.html" } },
            { path: "/index.html", target: { file: "content/index.html" } },
            { path: "/example.css", target: { file: "content/example.css" } },
            { path: "/example.js", target: { file: "content/example.js" } },
            { path: "/api/v1/data/animals", target: { dataset: "animals" } },
          ],
        },
        {
          datasets: [
            {
              name: "animals",
              source: "data/animals.yaml",
              format: "yaml",
              schema: "data/animals_schema.yaml",
            },
          ],
        }

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:cap_file)
      end
    end
  end
end
