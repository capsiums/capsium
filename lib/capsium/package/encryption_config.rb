# frozen_string_literal: true

require "lutaml/model"

module Capsium
  class Package
    # The "encryption" object of signature.json in an encrypted package
    # (05x-packaging "Encryption"): the AES-256-GCM envelope, all binary
    # values Base64-encoded. keyManagement selects how the data
    # encryption key (DEK) is protected: "RSA-OAEP-SHA256" carries it in
    # encryptedDek (RSA-wrapped); "OpenPGP" carries an armored OpenPGP
    # message containing the DEK in message.
    class EncryptionEnvelope < Lutaml::Model::Serializable
      attribute :algorithm, :string
      attribute :key_management, :string
      attribute :encrypted_dek, :string
      attribute :message, :string
      attribute :iv, :string
      attribute :auth_tag, :string

      json do
        map :algorithm, to: :algorithm
        map "keyManagement", to: :key_management
        map "encryptedDek", to: :encrypted_dek
        map :message, to: :message
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
