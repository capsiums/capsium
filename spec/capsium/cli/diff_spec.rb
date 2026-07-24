# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Capsium::Cli::Diff do
  let(:source_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(source_dir) if File.directory?(source_dir) }

  def write_package(name, files)
    dir = File.join(source_dir, name)
    FileUtils.mkdir_p(dir)
    files.each do |path, content|
      full = File.join(dir, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end
    dir
  end

  describe ".call (structural report)" do
    it "reports no differences for identical packages" do
      a = write_package("a", { "content/index.html" => "<html>a</html>" })
      b = write_package("b", { "content/index.html" => "<html>a</html>" })

      report = described_class.call(a, b)
      expect(report.routes.empty?).to be(true)
      expect(report.resources.empty?).to be(true)
      expect(report.datasets.empty?).to be(true)
    end

    it "reports added/removed/changed resources by content-addressed checksum" do
      a = write_package("a", {
                          "content/index.html" => "<html>old</html>",
                          "content/removed.html" => "<html>gone</html>"
                        })
      b = write_package("b", {
                          "content/index.html" => "<html>new</html>",
                          "content/added.html" => "<html>arrived</html>"
                        })

      report = described_class.call(a, b)
      expect(report.resources.added).to include("content/added.html")
      expect(report.resources.removed).to include("content/removed.html")
      expect(report.resources.changed).to include("content/index.html")
    end

    it "reports added/removed/changed routes" do
      a = write_package("a", {
                          "content/index.html" => "<html>a</html>",
                          "content/old.html" => "<html>old</html>",
                          "routes.json" => JSON.generate(
                            "routes" => [
                              { "path" => "/", "resource" => "content/index.html" },
                              { "path" => "/old", "resource" => "content/old.html" }
                            ]
                          )
                        })
      b = write_package("b", {
                          "content/index.html" => "<html>a</html>",
                          "content/new.html" => "<html>new</html>",
                          "routes.json" => JSON.generate(
                            "routes" => [
                              { "path" => "/", "resource" => "content/index.html" },
                              { "path" => "/new", "resource" => "content/new.html" }
                            ]
                          )
                        })

      report = described_class.call(a, b)
      expect(report.routes.added.map { |r| r[:path] }).to include("/new")
      expect(report.routes.removed.map { |r| r[:path] }).to include("/old")
    end

    it "reports added/removed/changed datasets" do
      a = write_package("a", {
                          "data/notes.json" => '[{"id":"1"}]',
                          "data/removed.json" => '[{"id":"1"}]',
                          "storage.json" => JSON.generate(
                            "storage" => {
                              "dataSets" => {
                                "notes" => { "source" => "data/notes.json" },
                                "removed" => { "source" => "data/removed.json" }
                              }
                            }
                          )
                        })
      b = write_package("b", {
                          "data/notes.json" => '[{"id":"1"},{"id":"2"}]',
                          "data/added.json" => '[{"id":"1"}]',
                          "storage.json" => JSON.generate(
                            "storage" => {
                              "dataSets" => {
                                "notes" => { "source" => "data/notes.json" },
                                "added" => { "source" => "data/added.json" }
                              }
                            }
                          )
                        })

      report = described_class.call(a, b)
      expect(report.datasets.added).to include("added")
      expect(report.datasets.removed).to include("removed")
      expect(report.datasets.changed).to include("notes")
    end
  end

  describe Capsium::Cli::Diff::Format do
    it "renders a non-empty diff with section labels and bullets" do
      a = write_package("a", { "content/index.html" => "<html>a</html>" })
      b = write_package("b", { "content/index.html" => "<html>b</html>",
                               "content/added.html" => "<html>x</html>" })
      report = Capsium::Cli::Diff.call(a, b)
      output = described_class.new(report).render
      expect(output).to include("Resources:")
      expect(output).to include("+ content/added.html")
      expect(output).to include("~ content/index.html")
    end

    it "renders '(no differences)' when packages match" do
      a = write_package("a", { "content/index.html" => "<html>x</html>" })
      b = write_package("b", { "content/index.html" => "<html>x</html>" })
      report = Capsium::Cli::Diff.call(a, b)
      expect(described_class.new(report).render).to eq("(no differences)")
    end
  end
end
