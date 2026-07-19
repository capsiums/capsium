# frozen_string_literal: true

module Capsium
  class Cli
    class Reactor < Thor
      extend ThorExt::Start

      desc "serve PACKAGE_PATH ...",
           "Start the Capsium reactor to serve one or more packages " \
           "(local packages, or capsium:// GUIDs installed from a registry)"
      option :port, type: :numeric, default: Capsium::Reactor::DEFAULT_PORT
      option :do_not_listen, type: :boolean, default: false
      option :store, type: :string,
                     desc: "Package store directory for dependency " \
                           "resolution (default: CAPSIUM_STORE)"
      option :deploy, type: :string,
                      desc: "deploy.json with reactor-side secrets " \
                            "(default: CAPSIUM_DEPLOY)"
      option :registry, type: :string,
                        desc: "Registry directory or https base URL for " \
                              "capsium:// GUIDs and dependency fallback " \
                              "(default: CAPSIUM_REGISTRY)"
      option :constraint, type: :string, default: "*",
                          desc: "Semver constraint for a capsium:// GUID"
      option :mount, type: :array,
                     desc: "Mount a source at a URL prefix, PATH=SOURCE " \
                           "(repeatable; sources without a prefix default " \
                           "to / for the first and /<name>/ for the rest)"
      option :config, type: :string,
                      desc: "JSON mount config: " \
                            '{"mounts": [{"path": "/", "source": "...", "store": "..."}]}'
      option :workdir, type: :string,
                       desc: "Reactor work directory for writable overlays " \
                             "and saved packages (default: a temporary directory)"

      # Thor array options are last-wins when the flag repeats; collect
      # every --mount value (both "--mount V" and "--mount=V" forms)
      # and re-emit one trailing occurrence so repetition accumulates.
      # (Subcommands are dispatched in-process, so this hooks dispatch,
      # not start; merging is idempotent for the direct-start flow.)
      def self.dispatch(meth, given_args, given_opts, config)
        super(meth, merge_mount_options(given_args),
              given_opts && merge_mount_options(given_opts), config)
      end

      def self.merge_mount_options(args)
        values = []
        rest = []
        index = 0
        while index < args.length
          arg = args[index]
          if arg == "--mount"
            index += 1
            while index < args.length && !args[index].start_with?("-")
              values << args[index]
              index += 1
            end
          elsif arg.start_with?("--mount=")
            values << arg.split("=", 2).last
            index += 1
          else
            rest << arg
            index += 1
          end
        end
        values.empty? ? args : rest + ["--mount"] + values
      end

      def serve(*sources)
        entries = mount_entries(sources)
        if entries.empty?
          raise Thor::Error, "no package source given (positional " \
                             "arguments, --mount or --config)"
        end

        mounts = Capsium::Reactor::Mount.build(
          entries, store: options[:store], registry: options[:registry]
        )
        reactor = Capsium::Reactor.new(
          mounts: mounts,
          port: options[:port],
          do_not_listen: options[:do_not_listen],
          store: options[:store],
          deploy: options[:deploy],
          registry: options[:registry],
          workdir: options[:workdir]
        )
        reactor.serve
      rescue Capsium::Error => e
        raise Thor::Error, e.message
      ensure
        reactor&.cleanup
      end

      private

      # The combined mount entries from --config, --mount and the
      # positional sources (in that order), with capsium:// GUIDs
      # installed from the registry into the store.
      def mount_entries(sources)
        entries = []
        entries.concat(Capsium::Reactor::Mount.config_entries(options[:config])) if options[:config]
        entries.concat(Array(options[:mount]).map do |spec|
          Capsium::Reactor::Mount.parse_spec(spec)
        end)
        entries.concat(sources.map do |source|
          Capsium::Reactor::Mount::Entry.new(path: nil, source: source, store: nil)
        end)
        entries.map do |entry|
          entry.with(source: resolve_source(entry.source))
        end
      end

      def resolve_source(source)
        return source unless source.start_with?("capsium://")

        install_from_registry(source)
      end

      # Install-then-serve for capsium:// GUIDs: resolve and install
      # from the registry into the package store, returning the
      # installed store .cap path.
      def install_from_registry(guid)
        registry = Capsium::Registry.fetch(options[:registry] || ENV.fetch("CAPSIUM_REGISTRY", nil))
        store = options[:store] || ENV.fetch("CAPSIUM_STORE", nil)
        if store.nil? || store.empty?
          raise Thor::Error,
                "no package store configured (pass --store or set CAPSIUM_STORE)"
        end

        path = registry.install(guid, options[:constraint], store: store)
        puts "Installed #{guid} to #{path}"
        path
      rescue Capsium::Registry::RegistryError => e
        raise Thor::Error, e.message
      end
    end
  end
end
