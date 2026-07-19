# frozen_string_literal: true

module Capsium
  class Error < StandardError; end

  autoload :VERSION, "capsium/version"
  autoload :Cli, "capsium/cli"
  autoload :Converters, "capsium/converters"
  autoload :Package, "capsium/package"
  autoload :Packager, "capsium/packager"
  autoload :Reactor, "capsium/reactor"
  autoload :Registry, "capsium/registry"
  autoload :ThorExt, "capsium/thor_ext"
end
