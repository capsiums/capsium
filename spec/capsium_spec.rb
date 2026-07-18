# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium do
  it "defines a semantic version" do
    expect(Capsium::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "defines an Error class" do
    expect(Capsium::Error.superclass).to eq(StandardError)
  end

  it "resolves the autoloaded public constants" do
    expect(Capsium::Package).to be_a(Class)
    expect(Capsium::Packager).to be_a(Class)
    expect(Capsium::Reactor).to be_a(Class)
    expect(Capsium::Protector).to be_a(Class)
    expect(Capsium::Cli).to be_a(Class)
    expect(Capsium::Converters::Jekyll).to be_a(Class)
  end

  it "resolves the package-internal constants through autoload" do
    expect(Capsium::Package::Manifest).to be_a(Class)
    expect(Capsium::Package::Metadata).to be_a(Class)
    expect(Capsium::Package::Routes).to be_a(Class)
    expect(Capsium::Package::Storage).to be_a(Class)
    expect(Capsium::Package::Dataset).to be_a(Class)
  end
end
