# frozen_string_literal: true

require File.expand_path("lib/capsium/version", __dir__)

Gem::Specification.new do |spec|
  spec.name = "capsium"
  spec.version = Capsium::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Packager and reactor for Capsium packages (.cap)"
  spec.description = "Capsium facilitates the creation, management and " \
                     "deployment of content packages with ease. This gem " \
                     "provides a structured way to handle content, data, " \
                     "and metadata for various applications: it packages " \
                     "them into .cap files and serves them over HTTP."
  spec.homepage = "https://github.com/capsiums/capsium"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/capsiums/capsium/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`
      .split("\x0")
      .reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.2.0"

  spec.add_dependency "csv"
  spec.add_dependency "json"
  spec.add_dependency "json-schema"
  spec.add_dependency "listen"
  spec.add_dependency "lutaml-model", ">= 0.8", "< 1.0"
  spec.add_dependency "marcel"
  spec.add_dependency "rubyzip", ">= 2.3.2", "< 4.0"
  spec.add_dependency "sqlite3"
  spec.add_dependency "thor"
  spec.add_dependency "webrick"
  spec.add_dependency "yaml"
end
