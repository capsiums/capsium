# frozen_string_literal: true

require "thor"

module Capsium
  class Cli < Thor
    extend ThorExt::Start

    autoload :Convert, "capsium/cli/convert"
    autoload :Diff, "capsium/cli/diff"
    autoload :Formatting, "capsium/cli/formatting"
    autoload :Init, "capsium/cli/init"
    autoload :Package, "capsium/cli/package"
    autoload :Reactor, "capsium/cli/reactor"

    desc "package SUBCOMMAND ...ARGS", "Manage packages"
    subcommand "package", Capsium::Cli::Package

    desc "reactor SUBCOMMAND ...ARGS", "Manage the reactor"
    subcommand "reactor", Capsium::Cli::Reactor

    desc "convert SUBCOMMAND ...ARGS", "Convert from another format"
    subcommand "convert", Capsium::Cli::Convert

    desc "init TEMPLATE NAME", "Scaffold a new Capsium package from a template"
    def init(template, name)
      result = Capsium::Cli::Init.call(template: template, name: name)
      puts "Created #{result.name} (template: #{result.template}) at #{result.path}"
      puts "Next: cd #{result.name} && capsium package validate ."
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "diff PACKAGE_A PACKAGE_B", "Show structural differences between two packages"
    option :json, type: :boolean, default: false, desc: "Emit machine-readable JSON"

    def diff(path_a, path_b)
      report = Capsium::Cli::Diff.call(path_a, path_b)
      if options[:json]
        puts JSON.pretty_generate(diff_to_h(report))
      else
        puts Capsium::Cli::Diff::Format.new(report).render
      end
    rescue Capsium::Error => e
      raise Thor::Error, e.message
    end

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

    desc "search [QUERY]", "List packages in the registry (optional fuzzy filter)"
    option :registry, type: :string,
                      desc: "Registry directory or https base URL " \
                            "(default: CAPSIUM_REGISTRY)"
    def search(query = nil)
      entries = registry_list
      filtered = query ? entries.select { |e| e[:name].include?(query) } : entries
      if filtered.empty?
        puts query ? "No packages match #{query.inspect}." : "Registry is empty."
        return
      end
      filtered.each do |entry|
        versions = entry[:versions].keys.sort.join(", ")
        puts "#{entry[:name].ljust(28)}  #{versions}  #{entry[:guid]}"
      end
    end

    desc "info GUID", "Show detailed info about one registry package"
    option :registry, type: :string,
                      desc: "Registry directory or https base URL " \
                            "(default: CAPSIUM_REGISTRY)"
    def info(guid)
      entry = registry_list.find { |e| e[:guid] == guid || e[:name] == guid }
      raise Thor::Error, "no package #{guid} in registry #{registry_location}" unless entry

      puts "name:     #{entry[:name]}"
      puts "guid:     #{entry[:guid]}"
      puts "versions:"
      entry[:versions].sort.each do |version, meta|
        puts "  #{version}:"
        puts "    file:    #{meta['file']}"
        puts "    sha256:  #{meta['sha256']}"
        puts "    size:    #{meta['size']} bytes"
      end
    end

    private

    def registry_list
      registry = Capsium::Registry.fetch(options[:registry] || ENV.fetch("CAPSIUM_REGISTRY", nil))
      registry.catalog.map { |e| { name: e.name, guid: e.guid, versions: e.versions } }
    rescue Capsium::Registry::RegistryError => e
      raise Thor::Error, e.message
    end

    def registry_location
      Capsium::Registry.fetch(options[:registry] || ENV.fetch("CAPSIUM_REGISTRY", nil)).location
    rescue Capsium::Registry::RegistryError
      "(unknown registry)"
    end

    def diff_to_h(report)
      {
        left: report.left,
        right: report.right,
        routes: report.routes.to_h,
        resources: report.resources.to_h,
        datasets: report.datasets.to_h
      }
    end

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
