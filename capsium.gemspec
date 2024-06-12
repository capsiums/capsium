# frozen_string_literal: true

require_relative "lib/capsium/version"

Gem::Specification.new do |spec|
  spec.name = "capsium"
  spec.version = Capsium::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Capsium"
  spec.description = "Capsium"
  spec.homepage = "https://github.com/metanorma/capsium"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/metanorma/capsium/releases"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`
      .split("\x0")
      .reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency "cssminify"
  spec.add_dependency "csv"
  spec.add_dependency "htmlcompressor"
  spec.add_dependency "html-proofer"
  spec.add_dependency "json"
  spec.add_dependency "listen"
  spec.add_dependency "marcel"
  spec.add_dependency "rubyzip", "~> 2.3.2"
  spec.add_dependency "scss_lint"
  spec.add_dependency "shale"
  spec.add_dependency "sqlite3"
  spec.add_dependency "thor"
  spec.add_dependency "uglifier"
  spec.add_dependency "webrick"
  spec.add_dependency "yaml"
  spec.add_dependency "jekyll"
  spec.add_dependency "json-schema"

  spec.add_development_dependency "rubocop-performance"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.11"
  spec.add_development_dependency "rubocop", "~> 1.58"
end
