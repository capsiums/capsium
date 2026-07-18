# frozen_string_literal: true

module Capsium
  class Cli
    class Reactor < Thor
      extend ThorExt::Start

      desc "serve PACKAGE_PATH",
           "Start the Capsium reactor to serve the package"
      option :port, type: :numeric, default: Capsium::Reactor::DEFAULT_PORT
      option :do_not_listen, type: :boolean, default: false

      def serve(path_to_package)
        reactor = Capsium::Reactor.new(
          package: path_to_package,
          port: options[:port],
          do_not_listen: options[:do_not_listen]
        )
        reactor.serve
      rescue StandardError => e
        puts e
        puts e.inspect
        puts e.backtrace
      ensure
        reactor&.package&.cleanup
      end
    end
  end
end
