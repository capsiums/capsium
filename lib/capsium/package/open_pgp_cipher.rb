# frozen_string_literal: true

require "base64"

module Capsium
  class Package
    # Encrypts and decrypts whole Capsium packages with OpenPGP key
    # management (ARCHITECTURE.md section 6b) through librnp
    # (Capsium::Package::OpenPgp). Parallel to the RSA-OAEP-SHA256
    # Cipher — same encrypted .cap layout, same AES-256-GCM content
    # encryption, same typed errors — with the DEK carried as an armored
    # OpenPGP message instead of an RSA-wrapped blob:
    #
    #   {"encryption": {"algorithm": "AES-256-GCM",
    #                   "keyManagement": "OpenPGP",
    #                   "message": <armored OpenPGP message with the DEK>,
    #                   "iv": <base64>, "authTag": <base64>}}
    #
    # Keys are OpenPGP key files (armored or binary, auto-detected):
    # encryption needs the recipient's public key, decryption the
    # secret key.
    class OpenPgpCipher < Cipher
      KEY_MANAGEMENT = "OpenPGP"

      # The OpenPGP symmetric cipher protecting the DEK message.
      CIPHER_NAME = "AES256"

      private

      # The encryption envelope carrying the DEK as an armored OpenPGP
      # message to the recipient's public key.
      def envelope_for(dek, gcm_iv, auth_tag, recipient)
        message = recipient.rnp.encrypt(
          input: Rnp::Input.from_string(dek),
          recipients: recipient.key, cipher: CIPHER_NAME, armored: true
        )
        EncryptionConfig.new(
          encryption: EncryptionEnvelope.new(
            algorithm: ALGORITHM, key_management: KEY_MANAGEMENT,
            message: message,
            iv: Base64.strict_encode64(gcm_iv), auth_tag: Base64.strict_encode64(auth_tag)
          )
        )
      end

      # Recovers the DEK by decrypting the envelope's OpenPGP message.
      # Reached only after the rnp binding loaded successfully (the
      # secret key is loaded first), so the Rnp error constants are
      # defined here.
      def unwrap_dek(envelope, secret_key)
        secret_key.rnp.decrypt(input: Rnp::Input.from_string(envelope.message.to_s))
      rescue Rnp::Error
        # No suitable key, or a malformed or tampered message.
        raise DecryptionError, "decryption failed: wrong key or tampered package"
      end

      def load_public_key(public_key_path)
        OpenPgp.load_key(public_key_path)
      end

      def load_private_key(private_key_path)
        OpenPgp.load_key(private_key_path, secret: true)
      end
    end
  end
end
