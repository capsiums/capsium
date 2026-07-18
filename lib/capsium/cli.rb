# frozen_string_literal: true

require "thor"

module Capsium
  class Cli < Thor
    extend ThorExt::Start

    autoload :Convert, "capsium/cli/convert"
    autoload :Package, "capsium/cli/package"
    autoload :Reactor, "capsium/cli/reactor"

    desc "package SUBCOMMAND ...ARGS", "Manage packages"
    subcommand "package", Capsium::Cli::Package

    desc "reactor SUBCOMMAND ...ARGS", "Manage the reactor"
    subcommand "reactor", Capsium::Cli::Reactor

    desc "convert SUBCOMMAND ...ARGS", "Convert from another format"
    subcommand "convert", Capsium::Cli::Convert
  end
end
