# frozen_string_literal: true

require_relative "capsium/version"
require "shale"
require "shale/adapter/nokogiri"
Shale.xml_adapter = Shale::Adapter::Nokogiri

module Capsium
  class Error < StandardError; end

  # Your code goes here...
end

require_relative "capsium/package"
require_relative "capsium/packager"
