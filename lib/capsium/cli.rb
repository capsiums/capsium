# frozen_string_literal: true

require "thor"

module Capsium
  class Cli < Thor
    extend ThorExt::Start

    autoload :Convert, "capsium/cli/convert"
    autoload :Formatting, "capsium/cli/formatting"
    autoload :Package, "capsium/cli/package"
    autoload :Reactor, "capsium/cli/reactor"

    desc "package SUBCOMMAND ...ARGS", "Manage packages"
    subcommand "package", Capsium::Cli::Package

    desc "reactor SUBCOMMAND ...ARGS", "Manage the reactor"
    subcommand "reactor", Capsium::Cli::Reactor

    desc "convert SUBCOMMAND ...ARGS", "Convert from another format"
    subcommand "convert", Capsium::Cli::Convert

    desc "install GUID", "Install a package from a registry into the package store"
    option :constraint, type: :string, default: "*",
                        desc: "Semver constraint the installed version must satisfy"
    option :registry, type: :string,
                      desc: "Registry directory or https base URL " \
                            "(default: CAPSIUM_REGISTRY)"
    option :store, type: :string,
                   desc: "Package store directory (default: CAPSIUM_STORE)"

    def install(guid)
      registry = Capsium::Registry.fetch(options[:registry] || ENV.fetch("CAPSIUM_REGISTRY", nil))
      path = registry.install(guid, options[:constraint], store: store_dir!)
      puts "Installed #{guid} to #{path}"
    rescue Capsium::Registry::RegistryError => e
      raise Thor::Error, e.message
    end

    private

    # The store directory for install-like commands: --store or
    # CAPSIUM_STORE, otherwise a typed CLI error.
    def store_dir!
      store = options[:store] || ENV.fetch("CAPSIUM_STORE", nil)
      return store unless store.nil? || store.empty?

      raise Thor::Error,
            "no package store configured (pass --store or set CAPSIUM_STORE)"
    end
  end
end
