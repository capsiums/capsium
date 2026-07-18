# frozen_string_literal: true

require "spec_helper"

RSpec.describe "lib/ architecture rules" do
  lib_root = File.expand_path("../lib", __dir__)
  lib_files = Dir.glob(File.join(lib_root, "**", "*.rb"))

  banned_patterns = {
    "require_relative" => /\brequire_relative\b/,
    "same-library require (use autoload)" => %r{\brequire\s*\(?\s*["']capsium/},
    "instance_variable_get/instance_variable_set" => /\binstance_variable_(?:get|set)\b/,
    "respond_to?" => /\brespond_to\?\b/,
    "send/__send__/public_send" => /\b__send__\b|\bpublic_send\b|(?<![\w.])send\s*\(|\.send\s*\(/
  }.freeze

  # Naive source scrubber: removes block comments, heredocs, string literals
  # and line comments so banned tokens inside prose or strings do not match.
  def strip_ruby_source(source)
    source = source.gsub(/^=begin\b.*?^=end\b/m, "")
    source = source.gsub(/<<[~-]?['"]?(\w+)['"]?[^\n]*\n.*?^\s*\1$/m, "")
    source = source.gsub(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, '""')
    source.gsub(/#.*$/, "")
  end

  it "scans at least one lib file" do
    expect(lib_files).not_to be_empty
  end

  banned_patterns.each do |rule, pattern|
    it "contains no #{rule}" do
      offenders = lib_files.select do |file|
        strip_ruby_source(File.read(file)).match?(pattern)
      end
      expect(offenders).to be_empty,
                           "#{rule} found in: #{offenders.join(', ')}"
    end
  end
end
