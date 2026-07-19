# frozen_string_literal: true

require "spec_helper"
require_relative "composite_spec_helper"

RSpec.describe Capsium::Package::Store do
  subject(:store) { described_class.new(store_dir) }

  let(:workdir) { Dir.mktmpdir }
  let(:store_dir) { CompositeSpecHelper.build_store(workdir) }

  after { FileUtils.rm_rf(workdir) }

  describe "#find" do
    it "resolves the newest satisfying version" do
      expect(store.find(CompositeSpecHelper::BASE_GUID, "^1.0.0"))
        .to end_with("base-package-1.2.0.cap")
      expect(store.find(CompositeSpecHelper::BASE_GUID, ">=1.0.0, <2.0.0"))
        .to end_with("base-package-1.2.0.cap")
      expect(store.find(CompositeSpecHelper::BASE_GUID, "*"))
        .to end_with("base-package-2.0.0.cap")
    end

    it "resolves tilde, wildcard and exact ranges" do
      expect(store.find(CompositeSpecHelper::BASE_GUID, "~1.0.0"))
        .to end_with("base-package-1.0.0.cap")
      expect(store.find(CompositeSpecHelper::BASE_GUID, "2.x"))
        .to end_with("base-package-2.0.0.cap")
      expect(store.find(CompositeSpecHelper::BASE_GUID, "1.2.0"))
        .to end_with("base-package-1.2.0.cap")
    end

    it "raises DependencyNotFoundError for an unknown GUID" do
      expect { store.find("https://example.com/capsiums/unknown", "*") }
        .to raise_error(Capsium::Package::DependencyNotFoundError, /unknown/)
    end

    it "raises UnsatisfiableDependencyError when no stored version matches" do
      expect { store.find(CompositeSpecHelper::BASE_GUID, ">=9.0.0") }
        .to raise_error(Capsium::Package::UnsatisfiableDependencyError,
                        />=9\.0\.0/)
    end
  end

  describe "index.json" do
    let(:store_dir) { CompositeSpecHelper.build_store(workdir, index: true) }

    it "pins an indexed GUID to the indexed file, still range-checked" do
      expect(store.find(CompositeSpecHelper::BASE_GUID, "^1.0.0"))
        .to end_with("base-package-1.0.0.cap")
      expect { store.find(CompositeSpecHelper::BASE_GUID, "^2.0.0") }
        .to raise_error(Capsium::Package::UnsatisfiableDependencyError)
    end

    it "falls back to scanning for GUIDs not in the index" do
      expect(store.find(CompositeSpecHelper::OTHER_GUID, "*"))
        .to end_with("other-package-0.9.0.cap")
    end
  end

  describe ".default" do
    it "reads CAPSIUM_STORE and stays nil when unset" do
      expect(described_class.default).to be_nil
      ENV["CAPSIUM_STORE"] = store_dir
      expect(described_class.default.dir).to eq(store_dir)
    ensure
      ENV.delete("CAPSIUM_STORE")
    end
  end

  it "rejects a missing store directory" do
    expect { described_class.new(File.join(workdir, "nope")) }
      .to raise_error(Capsium::Package::DependencyError, /not found/)
  end
end
