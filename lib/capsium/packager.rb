# frozen_string_literal: true

# lib/capsium/packager.rb
require "json"
require "fileutils"
require "rubygems"
require "zip"

module Capsium
  class Packager
    class FileAlreadyExistsError < StandardError; end

    def pack(package, options = {})
      package_name = package.metadata.name
      package_version = package.metadata.version
      cap_file_path = File.expand_path(
        File.join(package.path, "..", "#{package_name}-#{package_version}.cap")
      )

      if File.exist?(cap_file_path)
        unless options[:force]
          raise FileAlreadyExistsError,
                "Package target already exists, aborting: `#{relative_path_current(cap_file_path)}`"
        end

        puts "Package target already exists, overwriting: `#{relative_path_current(cap_file_path)}`"
        FileUtils.rm_f(cap_file_path)
      end

      Dir.mktmpdir do |dir|
        FileUtils.cp_r("#{package.path}/.", dir)
        new_package = Package.new(dir)
        new_package.solidify
        compress_package(new_package, cap_file_path)
        puts "Package created: #{relative_path_current(cap_file_path)}"
      end
    end

    def compress_package(package, cap_file)
      Zip::File.open(cap_file, Zip::File::CREATE) do |zipfile|
        Dir[File.join(package.path, "**", "**")].each do |file|
          zipfile.add(file.sub("#{package.path}/", ""), file)
        end
      end
    end

    # def package_files
    #   create_metadata_file
    #   create_manifest_file
    #   create_packaging_file

    #   compressor = Compressor.new(@package, @package.metadata[:compression])
    #   compressor.compress

    #   protector = Protector.new(@package, @package.metadata[:encryption], @package.metadata[:signature])
    #   protector.apply_encryption_and_sign
    # end

    # private

    # def create_metadata_file
    #   metadata_path = File.join(@package.path, Package::METADATA_FILE)
    #   metadata_content = @package.metadata.to_h
    #   write_json_file(metadata_path, metadata_content)
    # end

    # def create_manifest_file
    #   manifest_path = File.join(@package.path, Package::MANIFEST_FILE)
    #   manifest_content = {
    #     files: Dir[File.join(@package.path, '**', '*')].reject { |f| File.directory?(f) }
    #   }
    #   write_json_file(manifest_path, manifest_content)
    # end

    def create_packaging_file
      packaging_path = File.join(@package.path, Package::PACKAGING_FILE)
      packaging_content = {
        name: @package.name,
        content_path: relative_path_package(@package.content_path),
        data_path: relative_path_package(@package.data_path),
        datasets: @package.datasets.map(&:to_h)
      }
      write_json_file(packaging_path, packaging_content)
    end

    def write_json_file(path, content)
      File.open(path, "w") do |file|
        file.write(JSON.pretty_generate(content))
      end
    end

    def relative_path_package(absolute_path)
      Pathname.new(absolute_path).relative_path_from(Pathname.new(@package.path)).to_s
    end

    def relative_path_current(absolute_path)
      Pathname.new(absolute_path).relative_path_from(Dir.pwd).to_s
    end
  end
end
