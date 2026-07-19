# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Capsium::Reactor::Mount do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:bare_source) { File.join(fixtures_path, "bare-package") }
  let(:data_source) { File.join(fixtures_path, "data-package") }

  def entry(path, source, store: nil)
    described_class::Entry.new(path: path, source: source, store: store)
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
end
