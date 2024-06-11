# frozen_string_literal: true

# lib/capsium/converters/jekyll.rb
require "fileutils"
require "json"
require "capsium/package"

module Capsium
  module Converters
    class Jekyll
      def initialize(package_file, output_directory)
        @package_file = package_file
        @output_directory = output_directory
      end

      def convert
        package = Capsium::Package.new(@package_file)

        prepare_output_directory

        write_config_yml(package)
        copy_content_files(package)
        generate_index_html(package)

        puts "Capsium package converted to Jekyll site at #{@output_directory}"
      end

      private

      def prepare_output_directory
        FileUtils.mkdir_p(@output_directory)
      end

      def write_config_yml(package)
        config = {
          "title" => package.metadata.name || "Capsium Jekyll Site",
          "description" => package.metadata.description || "Generated from Capsium package",
          "baseurl" => "",
          "url" => "",
          "markdown" => "kramdown",
          "theme" => "minima",
        }
        write_file("_config.yml", config.to_yaml)
      end

      def write_file(relative_path, content)
        output_path = File.join(@output_directory, relative_path)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.open(output_path, "w") { |file| file.write(content) }
      end

      def copy_content_files(package)
        package.content_files.each do |file_path|
          relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(package.instance_variable_get(:@path)))
          output_path = File.join(@output_directory, relative_path)
          FileUtils.mkdir_p(File.dirname(output_path))
          FileUtils.cp(file_path, output_path)
        end
      end

      def generate_index_html(package)
        root_route = package.routes.config.routes.find { |route| route.path == "/" }
        if root_route
          index_path = File.join(package.instance_variable_get(:@path), root_route.target.file)
          index_content = File.read(index_path)
          write_file("index.html", index_content)
        else
          write_file("index.html", default_index_html(package))
        end
      end

      def default_index_html(package)
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <title>#{package.metadata.name || "Capsium Jekyll Site"}</title>
          </head>
          <body>
            <h1>Welcome to #{package.metadata.name || "Capsium Jekyll Site"}</h1>
            <p>This site was generated from a Capsium package.</p>
          </body>
          </html>
        HTML
      end
    end
  end
end
