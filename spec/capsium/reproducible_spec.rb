# frozen_string_literal: true

require "spec_helper"
require "digest"
require "fileutils"
require "tmpdir"

RSpec.describe "Capsium reproducible packaging" do
  let(:fixtures_path) { File.expand_path("fixtures", File.join(__dir__, "..")) }
  let(:source_path) { File.join(fixtures_path, "bare-package") }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def pack_once(target_dir, reproducible: false)
    # Copy the source so each iteration starts from a fresh on-disk
    # state (avoids carrying over a previous build's solidify /
    # security.json / sbom files).
    package_dir = File.join(@dir, target_dir)
    FileUtils.cp_r(source_path, package_dir)
    package = Capsium::Package.new(package_dir)
    options = { reproducible: reproducible, force: true }
    Capsium::Packager.new.pack(package, options)
  end

  def sha256_of(path)
    Digest::SHA256.file(path).hexdigest
  end

  it "produces a .cap archive" do
    path = pack_once("first")
    expect(File.file?(path)).to be(true)
  end

  it "non-reproducible mode: same inputs may produce different bytes" do
    skip "mtime variation is host-dependent; the contract is reproducible mode below"
  end

  it "reproducible mode: identical bytes across two runs" do
    first_path = pack_once("first", reproducible: true)
    second_path = pack_once("second", reproducible: true)

    first_sha = sha256_of(first_path)
    second_sha = sha256_of(second_path)
    expect(first_sha).to eq(second_sha),
                         "reproducible builds must produce byte-identical .cap archives"
  end

  it "reproducible mode: stable across a file mtime change" do
    first_path = pack_once("first", reproducible: true)
    first_sha = sha256_of(first_path)

    # Mutate mtimes (the content is unchanged, so the reproducible
    # build must ignore the filesystem's mtime signal).
    Dir.glob(File.join(@dir, "second", "**", "*").to_s).each do |path|
      next unless File.file?(path)

      File.utime(Time.at(1_580_000_000), Time.at(1_580_000_000), path)
    end

    second_path = pack_once("second", reproducible: true)
    second_sha = sha256_of(second_path)
    expect(first_sha).to eq(second_sha)
  end
end
