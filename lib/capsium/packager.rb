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
      directory = package.path
      cap_file_path = File.join(Dir.mktmpdir, "#{package.metadata.name}-#{package.metadata.version}.cap")

      if File.exist?(cap_file_path) && !options[:force]
        raise FileAlreadyExistsError, "Package target already exists, aborting: `#{cap_file_path}`"
      elsif File.exist?(cap_file_path)
        puts "Package target already exists, overwriting: `#{cap_file_path}`"
        FileUtils.rm_f(cap_file_path)
      end

      Dir.mktmpdir do |dir|
        FileUtils.cp_r("#{directory}/.", dir)
        new_package = Package.new(dir)
        new_package.solidify
        compress_package(new_package, cap_file_path)
        puts "Package created: #{cap_file_path}"
        return cap_file_path
      end
    end

    def unpack(cap_file_path, destination)
      Zip::File.open(cap_file_path) do |zip_file|
        zip_file.each do |entry|
          entry_path = File.join(destination, entry.name)
          FileUtils.mkdir_p(File.dirname(entry_path))
          entry.extract(entry_path)
        end
      end
    end

    def compress_package(package, cap_file)
      Zip::File.open(cap_file, Zip::File::CREATE) do |zipfile|
        Dir[File.join(package.path, "**", "**")].each do |file|
          zipfile.add(file.sub("#{package.path}/", ""), file)
        end
      end
    end

    def relative_path_current(absolute_path)
      Pathname.new(absolute_path).relative_path_from(Dir.pwd).to_s
    end
  end
end
