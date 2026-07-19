# frozen_string_literal: true

require "lutaml/model"

module Capsium
  class Package
    # The "integrityChecks" object of security.json (ARCHITECTURE.md
    # section 6): SHA-256 checksums over every package file except
    # security.json itself, keyed by package-relative path.
    class IntegrityChecks < Lutaml::Model::Serializable
      ALGORITHMS = %w[SHA-256].freeze

      attribute :checksum_algorithm, :string, values: ALGORITHMS, default: "SHA-256"
      attribute :checksums, :hash, default: {}

      json do
        map "checksumAlgorithm", to: :checksum_algorithm
        map :checksums, to: :checksums
      end
    end

    # The "digitalSignatures" object of security.json. Signing is a later
    # phase; the model parses the canonical fields only.
    class DigitalSignatures < Lutaml::Model::Serializable
      attribute :public_key, :string
      attribute :signature_file, :string

      json do
        map "publicKey", to: :public_key
        map "signatureFile", to: :signature_file
      end
    end

    # The "security" object of security.json.
    class SecurityData < Lutaml::Model::Serializable
      attribute :integrity_checks, IntegrityChecks
      attribute :digital_signatures, DigitalSignatures

      json do
        map "integrityChecks", to: :integrity_checks
        map "digitalSignatures", to: :digital_signatures
      end
    end

    # Canonical security.json model (generated at pack time).
    class SecurityConfig < Lutaml::Model::Serializable
      attribute :security, SecurityData

      json do
        map :security, to: :security
      end

      def checksums
        return {} unless security&.integrity_checks

        security.integrity_checks.checksums
      end
    end
  end
end
