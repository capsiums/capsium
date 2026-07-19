# frozen_string_literal: true

require "digest"
require "forwardable"
require "json"

module Capsium
  class Package
    # Loads, generates and verifies security.json (ARCHITECTURE.md
    # section 6). Checksums cover every file in the package except
    # security.json itself and signature.sig (the signature signs the
    # checksum-covered payload, so it cannot be part of it).
    class Security
      extend Forwardable

      class IntegrityError < Capsium::Error; end

      ChecksumMismatch = Data.define(:path, :expected, :actual) do
        def message
          "checksum mismatch: #{path}"
        end
      end
      MissingFile = Data.define(:path, :expected) do
        def message
          "checksum listed but file missing: #{path}"
        end
      end
      UncheckedFile = Data.define(:path) do
        def message
          "file not covered by checksums: #{path}"
        end
      end

      attr_reader :path, :config

      def_delegators :@config, :to_json, :to_hash

      def initialize(path, config = nil)
        @path = path
        @config = config || load_config
      end

      def self.generate(package_path, digital_signatures: nil)
        config = SecurityConfig.new(
          security: SecurityData.new(
            integrity_checks: IntegrityChecks.new(
              checksum_algorithm: "SHA-256",
              checksums: checksums_for(package_path)
            ),
            digital_signatures: digital_signatures
          )
        )
        new(File.join(package_path, SECURITY_FILE), config)
      end

      def self.checksums_for(package_path)
        package_files(package_path).sort.to_h do |relative_path|
          [relative_path, Digest::SHA256.file(File.join(package_path, relative_path)).hexdigest]
        end
      end

      def self.package_files(package_path)
        files = Dir.glob(File.join(package_path, "**", "*")).select do |file|
          File.file?(file)
        end
        files.map { |file| file.delete_prefix("#{package_path}/") }
             .reject { |relative_path| excluded?(relative_path) }
      end

      def self.excluded?(relative_path)
        [SECURITY_FILE, SIGNATURE_FILE].include?(relative_path)
      end

      def present?
        !@config.nil?
      end

      # The declared digitalSignatures block, or nil when absent.
      def digital_signatures
        return unless present? && config.security

        config.security.digital_signatures
      end

      def signed?
        !digital_signatures&.signature_file.nil?
      end

      def checksums
        present? ? config.checksums : {}
      end

      def verify(package_path)
        expected = checksums
        errors = verify_present_files(package_path, expected)
        expected.each do |relative_path, checksum|
          next if File.file?(File.join(package_path, relative_path))

          errors << MissingFile.new(path: relative_path, expected: checksum)
        end
        errors
      end

      def verify!(package_path)
        errors = verify(package_path)
        return if errors.empty?

        raise IntegrityError,
              "Package integrity check failed: #{errors.map(&:path).join(', ')}"
      end

      def save_to_file(output_path = @path)
        File.write(output_path, to_json)
      end

      private

      def load_config
        return unless File.exist?(@path)

        SecurityConfig.from_json(File.read(@path))
      end

      def verify_present_files(package_path, expected)
        self.class.package_files(package_path).filter_map do |relative_path|
          file_path = File.join(package_path, relative_path)
          if expected.key?(relative_path)
            actual = Digest::SHA256.file(file_path).hexdigest
            unless actual == expected[relative_path]
              next ChecksumMismatch.new(path: relative_path, expected: expected[relative_path],
                                        actual: actual)
            end
          else
            UncheckedFile.new(path: relative_path)
          end
        end
      end
    end
  end
end
