# frozen_string_literal: true

module Capsium
  class Package
    # Integrity and digital-signature verification of a loaded package
    # (ARCHITECTURE.md section 6), mixed into Package.
    module Verification
      # Verifies the package against security.json. Returns a list of
      # typed errors; empty when no security.json is present or all
      # checksums match.
      def verify_integrity
        @security.present? ? @security.verify(@path) : []
      end

      def verify_integrity!
        @security.verify!(@path) if @security.present?
      end

      # Whether security.json declares a digital signature for this package.
      def signed? = @security.signed?

      # Verifies the declared digital signature (RSA-SHA256) against the
      # checksum-covered payload. True when the package is unsigned (nothing
      # declared) or the signature verifies; false on mismatch.
      def verify_signature = !signed? || Signer.new(@path).verify

      def verify_signature!
        Signer.new(@path).verify! if signed?
      end
    end
  end
end
