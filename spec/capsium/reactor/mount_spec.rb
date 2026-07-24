# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Capsium::Reactor::Mount do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:bare_source) { File.join(fixtures_path, "bare-package") }
  let(:data_source) { File.join(fixtures_path, "data-package") }
  let(:readonly_source) { File.join(fixtures_path, "readonly-package") }

  def entry(path, source, store: nil, writable: nil)
    described_class::Entry.new(path: path, source: source, store: store,
                               writable: writable)
  end

  describe ".parse_spec" do
    it "parses PATH=SOURCE into an entry" do
      parsed = described_class.parse_spec("/data=/tmp/pkg")

      expect(parsed.path).to eq("/data")
      expect(parsed.source).to eq("/tmp/pkg")
      expect(parsed.store).to be_nil
    end

    it "keeps '=' inside the source" do
      parsed = described_class.parse_spec("/data=/tmp/a=b")

      expect(parsed.source).to eq("/tmp/a=b")
    end

    it "rejects malformed specs" do
      expect { described_class.parse_spec("no-separator") }
        .to raise_error(Capsium::Error, /PATH=SOURCE/)
      expect { described_class.parse_spec("=/tmp/pkg") }
        .to raise_error(Capsium::Error, /PATH=SOURCE/)
      expect { described_class.parse_spec("/data=") }
        .to raise_error(Capsium::Error, /PATH=SOURCE/)
    end
  end

  describe ".config_entries" do
    it "loads mounts from a JSON config file" do
      Dir.mktmpdir do |dir|
        config = File.join(dir, "mounts.json")
        File.write(config, JSON.generate(
                             "mounts" => [
                               { "path" => "/", "source" => bare_source },
                               { "path" => "/data", "source" => data_source,
                                 "store" => "/tmp/store" }
                             ]
                           ))

        entries = described_class.config_entries(config)

        expect(entries.size).to eq(2)
        expect(entries.first.path).to eq("/")
        expect(entries.first.source).to eq(bare_source)
        expect(entries.last.path).to eq("/data")
        expect(entries.last.store).to eq("/tmp/store")
      end
    end

    it "accepts writable: false per mount (operator opt-out)" do
      Dir.mktmpdir do |dir|
        config = File.join(dir, "mounts.json")
        File.write(config, JSON.generate(
                             "mounts" => [
                               { "path" => "/", "source" => bare_source,
                                 "writable" => false },
                               { "path" => "/data", "source" => data_source }
                             ]
                           ))

        entries = described_class.config_entries(config)

        expect(entries.first.writable).to be(false)
        expect(entries.last.writable).to be_nil
      end
    end

    it "rejects writable: true (operators cannot force writability over metadata)" do
      Dir.mktmpdir do |dir|
        config = File.join(dir, "mounts.json")
        File.write(config, JSON.generate(
                             "mounts" => [
                               { "path" => "/", "source" => bare_source,
                                 "writable" => true }
                             ]
                           ))
        expect { described_class.config_entries(config) }
          .to raise_error(Capsium::Error, /writable.*true is not allowed/)
      end
    end

    it "rejects non-boolean writable values" do
      Dir.mktmpdir do |dir|
        config = File.join(dir, "mounts.json")
        File.write(config, JSON.generate(
                             "mounts" => [
                               { "path" => "/", "source" => bare_source,
                                 "writable" => "yes" }
                             ]
                           ))
        expect { described_class.config_entries(config) }
          .to raise_error(Capsium::Error, /must be a boolean/)
      end
    end

    it "rejects malformed configs" do
      Dir.mktmpdir do |dir|
        config = File.join(dir, "mounts.json")
        File.write(config, "not json")
        expect { described_class.config_entries(config) }
          .to raise_error(Capsium::Error, /Invalid mount config/)

        File.write(config, JSON.generate("mounts" => [{ "path" => "/" }]))
        expect { described_class.config_entries(config) }
          .to raise_error(Capsium::Error, /source/)
      end
    end
  end

  describe ".build" do
    it "mounts the first source at / and additional ones at /<name>/" do
      mounts = described_class.build(
        [entry(nil, bare_source), entry(nil, data_source)]
      )

      expect(mounts.map(&:path)).to eq(["/", "/data-package"])
      expect(mounts.map { |mount| mount.package.name })
        .to eq(%w[bare-package data-package])
    end

    it "honors explicit paths" do
      mounts = described_class.build(
        [entry("/first", bare_source), entry("/second", data_source)]
      )

      expect(mounts.map(&:path)).to eq(["/first", "/second"])
    end

    it "normalizes paths (leading slash, no trailing slash)" do
      mounts = described_class.build([entry("data/", data_source)])

      expect(mounts.first.path).to eq("/data")
    end

    it "raises a MountConflictError for duplicate prefixes" do
      expect do
        described_class.build(
          [entry("/data", bare_source), entry("/data/", data_source)]
        )
      end.to raise_error(Capsium::Reactor::MountConflictError, %r{/data})
    end

    it "raises a MountConflictError when derived defaults collide" do
      Dir.mktmpdir do |dir|
        copy = File.join(dir, "data-copy")
        FileUtils.cp_r(data_source, copy)
        expect do
          described_class.build(
            [entry(nil, bare_source), entry(nil, data_source), entry(nil, copy)]
          )
        end.to raise_error(Capsium::Reactor::MountConflictError, %r{/data-package})
      end
    end

    it "cleans up already-loaded packages when a later source fails" do
      package = Capsium::Package.new(bare_source)
      allow(package).to receive(:cleanup)

      expect do
        described_class.build(
          [entry(nil, package), entry(nil, "/nonexistent/source")]
        )
      end.to raise_error(Capsium::Error, /Invalid package path/)

      expect(package).to have_received(:cleanup)
    end
  end

  describe "#matches? and #inner_path" do
    let(:root_mount) { described_class.new(path: "/", package: bare_source) }
    let(:named_mount) { described_class.new(path: "/data", package: data_source) }

    it "matches everything for the root mount" do
      expect(root_mount.matches?("/")).to be(true)
      expect(root_mount.matches?("/anything/else")).to be(true)
    end

    it "matches the prefix itself and paths below it" do
      expect(named_mount.matches?("/data")).to be(true)
      expect(named_mount.matches?("/data/index")).to be(true)
      expect(named_mount.matches?("/database")).to be(false)
      expect(named_mount.matches?("/other")).to be(false)
    end

    it "strips the prefix, mapping the bare prefix to /" do
      expect(named_mount.inner_path("/data")).to eq("/")
      expect(named_mount.inner_path("/data/index")).to eq("/index")
      expect(root_mount.inner_path("/index")).to eq("/index")
      expect(root_mount.inner_path("/")).to eq("/")
    end
  end

  describe "#writable? operator override (issue #27)" do
    let(:workdir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(workdir) if File.directory?(workdir) }

    it "is writable by default for a package without readOnly metadata" do
      mount = described_class.new(path: "/", package: bare_source,
                                  workdir: workdir)
      expect(mount.writable?).to be(true)
    end

    it "becomes read-only when writable: false is passed at construction" do
      mount = described_class.new(path: "/", package: bare_source,
                                  workdir: workdir, writable: false)
      expect(mount.writable?).to be(false)
    end

    it "becomes read-only when writable_override is set to false post-construction" do
      mount = described_class.new(path: "/", package: bare_source,
                                  workdir: workdir)
      expect(mount.writable?).to be(true)

      mount.writable_override = false
      expect(mount.writable?).to be(false)
    end

    it "stays read-only for a readOnly: true package even without override" do
      mount = described_class.new(path: "/", package: readonly_source,
                                  workdir: workdir)
      expect(mount.writable?).to be(false)
    end
  end
end
