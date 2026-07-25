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

      desc "astro SOURCE_DIR [OUTPUT_DIR]",
           "Convert an Astro-built static site (dist/) to a Capsium package"
      option :name, type: :string, desc: "Package metadata.name (default: source dir basename)"
      option :exclude, type: :array, default: [],
                       desc: "Extra path globs to skip beyond Astro's build artifacts"

      def astro(source_dir, output_dir = nil)
        convert_ssg(Capsium::Converters::Astro, source_dir, output_dir)
      end

      desc "hugo SOURCE_DIR [OUTPUT_DIR]",
           "Convert a Hugo-built static site (public/) to a Capsium package"
      option :name, type: :string, desc: "Package metadata.name (default: source dir basename)"
      option :exclude, type: :array, default: [],
                       desc: "Extra path globs to skip beyond Hugo's build artifacts"

      def hugo(source_dir, output_dir = nil)
        convert_ssg(Capsium::Converters::Hugo, source_dir, output_dir)
      end

      desc "next SOURCE_DIR [OUTPUT_DIR]",
           "Convert a Next.js static export (out/) to a Capsium package"
      option :name, type: :string, desc: "Package metadata.name (default: source dir basename)"
      option :exclude, type: :array, default: [],
                       desc: "Extra path globs to skip beyond Next.js build artifacts"

      def next(source_dir, output_dir = nil)
        convert_ssg(Capsium::Converters::NextJs, source_dir, output_dir)
      end

      private

      def convert_ssg(converter_class, source_dir, output_dir)
        result = converter_class.new(source_dir: source_dir,
                                     output_dir: output_dir,
                                     package_name: options[:name],
                                     exclude: options[:exclude]).convert
        puts "Converted #{result.source} → #{result.output} " \
             "(#{result.routes_added} routes, #{result.assets_copied} assets)"
        puts "Next: cd #{File.basename(result.output)} && capsium package validate ."
      rescue ArgumentError => e
        raise Thor::Error, e.message
      end
    end
  end
end
