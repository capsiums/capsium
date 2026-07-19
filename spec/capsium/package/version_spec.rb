# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium::Package::Version do
  describe ".parse" do
    it "parses release, prerelease and build forms" do
      expect(described_class.parse("1.2.3").to_s).to eq("1.2.3")
      expect(described_class.parse("1.2.3-alpha").to_s).to eq("1.2.3-alpha")
      expect(described_class.parse("1.2.3-alpha+build.5").to_s).to eq("1.2.3-alpha")
    end

    it "rejects invalid versions" do
      expect { described_class.parse("1.2") }.to raise_error(Capsium::Error)
      expect { described_class.parse("v1.2.3") }.to raise_error(Capsium::Error)
      expect { described_class.parse("1.2.3.4") }.to raise_error(Capsium::Error)
    end
  end

  describe "#<=>" do
    it "orders by semver precedence (semver.org item 11)" do
      versions = %w[1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta
                    1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0]
      versions.each_cons(2) do |lower, higher|
        expect(described_class.parse(lower)).to be < described_class.parse(higher)
      end
      parsed = versions.map { |string| described_class.parse(string) }
      expect(parsed.shuffle.sort).to eq(parsed)
    end

    it "orders numerically within each segment" do
      expect(described_class.parse("1.9.0")).to be < described_class.parse("1.10.0")
    end

    it "ignores build metadata for precedence" do
      expect(described_class.parse("1.0.0+build.1"))
        .to eq(described_class.parse("1.0.0+build.2"))
    end
  end
end

RSpec.describe Capsium::Package::VersionRange do
  def satisfying(range, versions)
    versions.select { |version| described_class.parse(range).satisfied_by?(version) }
  end

  it '"*" satisfies any version' do
    expect(satisfying("*", %w[0.0.1 1.2.3 9.9.9])).to eq(%w[0.0.1 1.2.3 9.9.9])
  end

  it "matches exact versions" do
    expect(satisfying("1.2.3", %w[1.2.3 1.2.4 1.2.2])).to eq(%w[1.2.3])
  end

  it "matches comparison operators" do
    expect(satisfying(">=1.0.0", %w[0.9.9 1.0.0 2.0.0])).to eq(%w[1.0.0 2.0.0])
    expect(satisfying(">1.0.0", %w[1.0.0 1.0.1])).to eq(%w[1.0.1])
    expect(satisfying("<=1.0.0", %w[0.9.9 1.0.0 1.0.1])).to eq(%w[0.9.9 1.0.0])
    expect(satisfying("<2.0.0", %w[1.9.9 2.0.0])).to eq(%w[1.9.9])
    expect(satisfying("=1.0.0", %w[1.0.0 1.0.1])).to eq(%w[1.0.0])
    expect(satisfying("==1.0.0", %w[1.0.0 1.0.1])).to eq(%w[1.0.0])
  end

  it "matches caret ranges" do
    expect(satisfying("^1.2.3", %w[1.2.2 1.2.3 1.9.0 2.0.0])).to eq(%w[1.2.3 1.9.0])
    expect(satisfying("^0.2.3", %w[0.2.3 0.2.9 0.3.0])).to eq(%w[0.2.3 0.2.9])
    expect(satisfying("^0.0.3", %w[0.0.3 0.0.4])).to eq(%w[0.0.3])
    expect(satisfying("^1", %w[0.9.9 1.0.0 1.9.9 2.0.0])).to eq(%w[1.0.0 1.9.9])
  end

  it "matches tilde ranges" do
    expect(satisfying("~1.2.3", %w[1.2.3 1.2.9 1.3.0])).to eq(%w[1.2.3 1.2.9])
    expect(satisfying("~1.2", %w[1.2.0 1.2.9 1.3.0])).to eq(%w[1.2.0 1.2.9])
    expect(satisfying("~1", %w[1.0.0 1.9.9 2.0.0])).to eq(%w[1.0.0 1.9.9])
  end

  it "matches wildcards and partials" do
    expect(satisfying("1.x", %w[0.9.9 1.0.0 1.9.9 2.0.0])).to eq(%w[1.0.0 1.9.9])
    expect(satisfying("1.2.x", %w[1.2.0 1.2.9 1.3.0])).to eq(%w[1.2.0 1.2.9])
    expect(satisfying("1.2", %w[1.2.0 1.2.9 1.3.0])).to eq(%w[1.2.0 1.2.9])
    expect(satisfying("1", %w[1.0.0 1.9.9 2.0.0])).to eq(%w[1.0.0 1.9.9])
  end

  it "matches conjunctions joined by comma and/or space" do
    versions = %w[0.9.9 1.0.0 1.5.0 2.0.0]
    expect(satisfying(">=1.0.0, <2.0.0", versions)).to eq(%w[1.0.0 1.5.0])
    expect(satisfying(">=1.0.0 <2.0.0", versions)).to eq(%w[1.0.0 1.5.0])
  end

  it "compares prereleases by semver precedence" do
    expect(satisfying(">=1.0.0-alpha", %w[1.0.0-alpha 1.0.0]))
      .to eq(%w[1.0.0-alpha 1.0.0])
  end

  it "rejects invalid range terms" do
    expect { described_class.parse("abc") }.to raise_error(Capsium::Error)
    expect { described_class.parse(">=x") }.to raise_error(Capsium::Error)
  end
end
