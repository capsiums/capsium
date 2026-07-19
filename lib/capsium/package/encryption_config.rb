# frozen_string_literal: true

require "lutaml/model"

module Capsium
  class Package
    # The "encryption" object of signature.json in an encrypted package
    # (05x-packaging "Encryption"): the AES-256-GCM envelope with the
    # RSA-OAEP-SHA256 wrapped data encryption key (DEK), all binary
    # values Base64-encoded.
    class EncryptionEnvelope < Lutaml::Model::Serializable
      attribute :algorithm, :string
      attribute :key_management, :string
      attribute :encrypted_dek, :string
      attribute :iv, :string
      attribute :auth_tag, :string

      json do
        map :algorithm, to: :algorithm
        map "keyManagement", to: :key_management
        map "encryptedDek", to: :encrypted_dek
        map :iv, to: :iv
        map "authTag", to: :auth_tag
      end
    end

    # The signature.json file of an encrypted package. In this phase it
    # carries only the encryption envelope (digital signatures over
    # encrypted packages are a later phase).
    class EncryptionConfig < Lutaml::Model::Serializable
      attribute :encryption, EncryptionEnvelope

      json do
        map :encryption, to: :encryption
      end
    end
  end
end
