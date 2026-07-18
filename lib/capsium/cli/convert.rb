# frozen_string_literal: true

module Capsium
  class Cli
    class Convert < Thor
      extend ThorExt::Start

      desc "jekyll PACKAGE_FILE OUTPUT_DIRECTORY",
           "Convert a Capsium package to a Jekyll site"

      def jekyll(package_file, output_directory)
        converter = Capsium::Converters::Jekyll.new(package_file,
                                                    output_directory)
        converter.convert
      end
    end
  end
end
