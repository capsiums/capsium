# frozen_string_literal: true

require "digest"

module Capsium
  class Package
    # Integrity and digital-signature verification of a loaded package
    # (ARCHITECTURE.md section 6), mixed into Package.
    module Verification
      # Verifies the package against security.json. Returns a list of
      # typed errors; empty when no security.json is present or all
      # checksums match. Streaming packages verify against the .cap zip
      # entries (the only files on disk in that mode are config files).
      def verify_integrity
        return [] unless @security.present?
        return verify_integrity_from_zip if @streaming && @zip_source_path

        @security.verify(@path)
      end

      def verify_integrity!
        errors = verify_integrity
        return if errors.empty?

        raise Security::IntegrityError,
              "Package integrity check failed: #{errors.map(&:path).join(', ')}"
      end

      # Whether security.json declares a digital signature for this package.
      def signed? = @security.signed?

      # Verifies the declared digital signature against the
      # checksum-covered payload, through the signer matching the
      # declared certificateType (OpenPgpSigner for OpenPGP, the
      # RSA-SHA256 Signer otherwise). True when the package is unsigned
      # (nothing declared) or the signature verifies; false on mismatch.
      def verify_signature = !signed? || Signer.signer_class_for(@path).new(@path).verify

      def verify_signature!
        Signer.signer_class_for(@path).new(@path).verify! if signed?
      end

      private

      # Streaming-mode integrity check: reads each checksummed file
      # directly from the .cap zip. The zip is the source of truth in
      # streaming mode (the package tempdir holds config files only).
      def verify_integrity_from_zip
        require "zip"
        expected = @security.checksums
        errors = []
        Zip::File.open(@zip_source_path) do |zip|
          expected.each do |relative_path, expected_checksum|
            entry = zip.find_entry(relative_path)
            unless entry
              errors << Security::MissingFile.new(path: relative_path,
                                                  expected: expected_checksum)
              next
            end
            actual = Digest::SHA256.hexdigest(entry.get_input_stream.read)
            next if actual == expected_checksum

            errors << Security::ChecksumMismatch.new(path: relative_path,
                                                     expected: expected_checksum,
                                                     actual: actual)
          end
        end
        errors
      end
    end
  end
end
