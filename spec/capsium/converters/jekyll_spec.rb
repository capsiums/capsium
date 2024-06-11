# frozen_string_literal: true

require "spec_helper"
require "capsium/converters/jekyll"

RSpec.describe Capsium::Converters::Jekyll do
  let(:package_file) { "spec/fixtures/bare_package-0.1.0.cap" }
  let(:output_directory) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry output_directory
  end

  describe "#convert" do
    it "converts a Capsium package to a Jekyll site" do
      converter = described_class.new(package_file, output_directory)
      converter.convert

      expect(File).to exist(File.join(output_directory, "_config.yml"))
      expect(File).to exist(File.join(output_directory, "index.html"))
    end
  end
end
