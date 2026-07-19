# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium::Reactor::Htpasswd do
  let(:htpasswd_path) { File.join(Dir.mktmpdir, ".htpasswd") }

  after { FileUtils.rm_rf(File.dirname(htpasswd_path)) }

  def write_entries(entries)
    File.write(htpasswd_path, entries.map { |entry| entry.join(":") }.join("\n"))
    described_class.new(htpasswd_path)
  end

  it "verifies bcrypt hashes (htpasswd -B), including the $2y$ tag" do
    hash = BCrypt::Password.create("rabbit", cost: 10)
    htpasswd = write_entries([["alice", hash]])
    expect(htpasswd.verify?("alice", "rabbit")).to be(true)
    expect(htpasswd.verify?("alice", "wrong")).to be(false)

    hashed_2y = write_entries([["alice", hash.sub("$2a$", "$2y$")]])
    expect(hashed_2y.verify?("alice", "rabbit")).to be(true)
  end

  it "verifies Apache apr1 MD5 hashes (htpasswd -m)" do
    # Generated with: openssl passwd -apr1 -salt eWvS2f3d rabbit
    htpasswd = write_entries([["carol", "$apr1$eWvS2f3d$cIzGMbXvy2j6rwuon5lJP."]])
    expect(htpasswd.verify?("carol", "rabbit")).to be(true)
    expect(htpasswd.verify?("carol", "wrong")).to be(false)
  end

  it "verifies md5-crypt hashes ($1$)" do
    # Generated with: openssl passwd -1 -salt saltsalt42 rabbit
    htpasswd = write_entries([["dave", "$1$saltsalt$czbX58I2vBxI8rdYAdIYd."]])
    expect(htpasswd.verify?("dave", "rabbit")).to be(true)
    expect(htpasswd.verify?("dave", "wrong")).to be(false)
  end

  it "verifies unsalted SHA-1 hashes ({SHA}, htpasswd -s)" do
    htpasswd = write_entries([["erin", "{SHA}bQ67vc4yR024FB0j0sAb2WKNbl8="]])
    expect(htpasswd.verify?("erin", "rabbit")).to be(true)
    expect(htpasswd.verify?("erin", "wrong")).to be(false)
  end

  it "returns false for unknown users and skips comments" do
    htpasswd = write_entries([["# a comment"], ["alice", BCrypt::Password.create("rabbit")]])
    expect(htpasswd.verify?("mallory", "rabbit")).to be(false)
    expect(htpasswd.usernames).to eq(["alice"])
  end

  it "raises a Capsium::Error for a missing file" do
    expect { described_class.new(File.join(Dir.mktmpdir, "nope")) }
      .to raise_error(Capsium::Error, /htpasswd file not found/)
  end
end
