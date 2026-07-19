# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"
require "zip"

module Capsium
  class Packager
    class FileAlreadyExistsError < StandardError; end

    # Raised when a .cap archive contains an entry whose name would be
    # written outside the destination directory (absolute paths, drive
    # letters, ".." segments) — zip-slip protection, on par with the Lua
    # reactor's extractor.
    class UnsafeEntryError < Capsium::Error; end

    DRIVE_LETTER_PATTERN = %r{\A[A-Za-z]:[/\\]}
    DOT_ENTRIES = [".", ".."].freeze

    def pack(package, options = {})
      output_file_name = "#{package.metadata.name}-#{package.metadata.version}.cap"
      cap_file_path = File.join(File.dirname(package.path), output_file_name)
      check_target(cap_file_path, options)

      Dir.mktmpdir do |dir|
        build_cap(package, dir, output_file_name, options)
        FileUtils.mv(File.join(dir, output_file_name), cap_file_path)
        puts "Package created: #{relative_path_current(cap_file_path)}"
        return cap_file_path
      end
    end

    def unpack(cap_file_path, destination)
      destination = File.expand_path(destination)
      Zip::File.open(cap_file_path) do |zip_file|
        zip_file.each do |entry|
          entry_path = safe_entry_path(destination, entry.name)
          FileUtils.mkdir_p(File.dirname(entry_path))
          entry.extract(entry_path)
        end
      end
    end

    def compress_package(package, cap_file)
      entries = Dir.glob(File.join(package.path, "**", "**"), File::FNM_DOTMATCH).reject do |file|
        File.expand_path(file) == File.expand_path(cap_file) ||
          DOT_ENTRIES.include?(File.basename(file))
      end
      Zip::File.open(cap_file, create: true) do |zipfile|
        entries.each do |file|
          zipfile.add(file.sub("#{package.path}/", ""), file)
        end
      end
    end

    # Unpacks a .cap into a temporary directory, yields it for read-only
    # inspection and returns the block's value.
    def with_unpacked_cap(cap_path)
      Dir.mktmpdir do |dir|
        unpack(cap_path, dir)
        yield dir
      end
    end

    # Unpacks a .cap into a temporary directory, yields it for
    # modification, then recompresses the result back over cap_path.
    # The modified package is loaded (verifying integrity and any
    # declared signature) before recompressing.
    def transform_cap(cap_path)
      with_unpacked_cap(cap_path) do |dir|
        yield dir
        Dir.mktmpdir do |tmp|
          tmp_cap = File.join(tmp, File.basename(cap_path))
          compress_package(Package.new(dir), tmp_cap)
          FileUtils.mv(tmp_cap, cap_path)
        end
      end
      cap_path
    end

    def relative_path_current(absolute_path)
      Pathname.new(absolute_path).relative_path_from(Dir.pwd).to_s
    end

    private

    # Guards the pack target: without :force an existing .cap aborts,
    # with :force it is removed first.
    def check_target(cap_file_path, options)
      if File.exist?(cap_file_path) && !options[:force]
        raise FileAlreadyExistsError,
              "Package target already exists, aborting: `#{relative_path_current(cap_file_path)}`"
      end
      return unless File.exist?(cap_file_path)

      puts "Package target already exists, overwriting: `#{relative_path_current(cap_file_path)}`"
      FileUtils.rm_f(cap_file_path)
    end

    # Builds the .cap inside the temporary directory: copy, optional
    # dependency bundling, solidify, security.json, compress.
    def build_cap(package, directory, output_file_name, options)
      FileUtils.cp_r("#{package.path}/.", directory)
      strip_security_artifacts(directory)
      bundle_dependencies(directory, options) if options[:bundle_deps]
      new_package = load_packed_package(directory, options)
      new_package.solidify
      generate_security(new_package)
      built_path = File.join(directory, output_file_name)
      compress_package(new_package, built_path)
      puts "Package built at: #{built_path}"
    end

    # Loads the copied package directory for solidification, with the
    # pack-time store/registry available for dependency resolution.
    def load_packed_package(directory, options)
      Package.new(directory, store: options[:store], registry: options[:registry])
    end

    # Encapsulated packing (`pack --bundle-deps`): resolves every
    # declared dependency through the store -> registry chain and embeds
    # the resolved .cap files under packages/ (Capsium::Package::Bundle),
    # so the packed package activates with no store or registry. Only
    # the declared dependencies are bundled — the one-level policy: the
    # parent's metadata.dependencies must list the transitive closure.
    # Typed dependency errors (DependencyNotFoundError,
    # UnsatisfiableDependencyError) propagate for unresolvable
    # dependencies.
    def bundle_dependencies(directory, options)
      metadata = Package::Metadata.new(File.join(directory, Package::METADATA_FILE))
      declared = metadata.dependencies
      return if declared.empty?

      resolver = Package::DependencyResolver.new(
        options[:store] || Package::Store.default, registry: options[:registry]
      )
      resolutions = declared.map do |guid, range|
        [guid, resolver.resolve_path(guid, range, chain: [metadata.guid])]
      end
      Package::Bundle.write(directory, resolutions)
    end

    # Resolves an entry name against the destination and returns the
    # absolute target path, raising UnsafeEntryError when the entry would
    # escape the destination (zip-slip).
    def safe_entry_path(destination, entry_name)
      entry_path = File.expand_path(entry_name, destination)
      return entry_path if contained?(entry_path, destination) &&
                           !entry_name.match?(DRIVE_LETTER_PATTERN)

      raise UnsafeEntryError,
            "Refusing to extract unsafe zip entry: #{entry_name}"
    end

    def contained?(entry_path, destination)
      entry_path.start_with?("#{destination}#{File::SEPARATOR}")
    end

    def generate_security(package)
      security = Package::Security.generate(package.path)
      security.save_to_file
    end

    # security.json is regenerated on pack; signing artifacts are dropped
    # because signing is a post-pack step (`capsium package sign`).
    def strip_security_artifacts(directory)
      FileUtils.rm_f(File.join(directory, Package::SECURITY_FILE))
      FileUtils.rm_f(File.join(directory, Package::SIGNATURE_FILE))
      FileUtils.rm_f(File.join(directory, Package::Signer::PUBLIC_KEY_FILE))
    end
  end
end
