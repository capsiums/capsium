# frozen_string_literal: true

module Capsium
  class Cli
    class Reactor < Thor
      extend ThorExt::Start

      desc "serve PACKAGE_PATH",
           "Start the Capsium reactor to serve the package (a local " \
           "package, or a capsium:// GUID installed from a registry)"
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

      def serve(path_to_package)
        if path_to_package.start_with?("capsium://")
          path_to_package = install_from_registry(path_to_package)
        end
        reactor = Capsium::Reactor.new(
          package: path_to_package,
          port: options[:port],
          do_not_listen: options[:do_not_listen],
          store: options[:store],
          deploy: options[:deploy],
          registry: options[:registry]
        )
        reactor.serve
      ensure
        reactor&.package&.cleanup
      end

      private

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
