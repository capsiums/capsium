# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Capsium
  class Package
    # Package-source preparation (ARCHITECTURE.md section 1), mixed into
    # Package: directory/.cap/encrypted-cap detection, extraction and
    # decryption into a readable package directory.
    module Preparation
      def prepare_package(path)
        return decrypt_cap_file(path) if Cipher.encrypted?(path)
        return path if File.directory?(path)
        raise Error, "Invalid package path: #{path}" unless File.file?(path)
        raise Error, "The package must have a .cap extension" unless File.extname(path) == ".cap"

        decompress_cap_file(path)
      end

      def decompress_cap_file(file_path)
        package_path = File.join(Dir.mktmpdir, package_stem(file_path))
        FileUtils.mkdir_p(package_path)
        Packager.new.unpack(file_path, package_path)
        package_path
      end

      # Decrypts an encrypted package (.cap file or uncompressed directory)
      # into a temporary directory and returns its path. The metadata.json
      # of an encrypted package stays cleartext, but everything else is
      # only readable with the recipient's private key.
      def decrypt_cap_file(source_path)
        unless @decryption_key
          raise Cipher::KeyRequiredError,
                "Package is encrypted; provide the private key via decryption_key:"
        end

        Cipher.decrypt_to_directory(source_path, @decryption_key)
      end

      def determine_load_type(path)
        return :directory if File.directory?(path)

        File.extname(path) == ".cap" ? :cap_file : :unsaved
      end

      private

      def package_stem(file_path)
        File.basename(file_path, ".cap")
      end

      def create_package_structure
        FileUtils.mkdir_p(content_path)
        FileUtils.mkdir_p(data_path)
      end

      def content_path = File.join(@path, CONTENT_DIR)

      def data_path = File.join(@path, DATA_DIR)

      def routes_path = File.join(@path, ROUTES_FILE)

      def storage_path = File.join(@path, STORAGE_FILE)

      def metadata_path = File.join(@path, METADATA_FILE)

      def manifest_path = File.join(@path, MANIFEST_FILE)

      def security_path = File.join(@path, SECURITY_FILE)

      def authentication_path = File.join(@path, AUTHENTICATION_FILE)
    end
  end
end
