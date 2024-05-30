# frozen_string_literal: true

require_relative "capsium/version"

module Capsium
  class Error < StandardError; end

  # Your code goes here...
end

require_relative "capsium/package"
require_relative "capsium/packager"
