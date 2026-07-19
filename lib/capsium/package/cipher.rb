# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "openssl"
require "tmpdir"
require "zip"

module Capsium
  class Package
    # Encrypts and decrypts whole Capsium packages (05x-packaging
    # "Encryption", 05x-security "Encrypted information").
    #
    # An encrypted .cap is a zip containing exactly:
    #
    #   metadata.json   (cleartext, per the standard: name/version stay
    #                    readable without the key)
    #   signature.json  (the encryption envelope)
    #   package.enc     (AES-256-GCM ciphertext of the inner, plaintext
    #                    .cap zip holding content/, the configuration
    #                    files and data/)
    #
    # The envelope:
    #
    #   {"encryption": {"algorithm": "AES-256-GCM",
    #                   "keyManagement": "RSA-OAEP-SHA256",
    #                   "encryptedDek": <base64>, "iv": <base64>,
    #                   "authTag": <base64>}}
    #
    # A random 256-bit data encryption key (DEK) encrypts the inner zip;
    # the DEK is wrapped with the recipient's RSA public key using OAEP
    # with SHA-256 (MGF1-SHA-256). OpenPGP key management (an armored
    # OpenPGP message carrying the DEK) is provided by the parallel
    # OpenPgpCipher subclass; the OCB alternative mentioned by the
    # standard remains out of scope.
    class Cipher
      ALGORITHM = "AES-256-GCM"
      KEY_MANAGEMENT = "RSA-OAEP-SHA256"
      ENCRYPTED_FILE = "package.enc"
      ENVELOPE_FILE = "signature.json"
      RSA_OPTIONS = { "rsa_padding_mode" => "oaep",
                      "rsa_oaep_md" => "SHA256", "rsa_mgf1_md" => "SHA256" }.freeze

      # Structural problems: unreadable input, missing zip entries,
      # unsupported envelope algorithms, unloadable keys.
      class CipherError < Capsium::Error; end

      # An encrypted package was opened without a private key.
      class KeyRequiredError < CipherError; end

      # Decryption failed: wrong private key or tampered ciphertext.
      class DecryptionError < CipherError; end

      # Whether the path (.cap file or uncompressed directory) is an
      # encrypted package, i.e. contains package.enc.
      def self.encrypted?(path)
        return File.file?(File.join(path, ENCRYPTED_FILE)) if File.directory?(path)
        return false unless File.file?(path)

        Zip::File.open(path) { |zip| !zip.find_entry(ENCRYPTED_FILE).nil? }
      rescue Zip::Error
        false
      end

      # The keyManagement declared by the encryption envelope of the
      # path (.cap file or uncompressed directory), or nil when the
      # envelope is absent or unreadable.
      def self.key_management(path)
        source = envelope_source(path)
        source && EncryptionConfig.from_json(source).encryption&.key_management
      rescue Lutaml::Model::Error, JSON::ParserError
        nil
      end

      # The cipher instance matching the envelope's keyManagement:
      # OpenPgpCipher for OpenPGP envelopes, the RSA cipher otherwise.
      def self.for_encrypted(path)
        key_management(path) == OpenPgpCipher::KEY_MANAGEMENT ? OpenPgpCipher.new : new
      end

      def self.envelope_source(path)
        envelope = File.join(path, ENVELOPE_FILE)
        return File.read(envelope) if File.directory?(path) && File.file?(envelope)
        return nil if File.directory?(path)

        Zip::File.open(path) { |zip| zip.find_entry(ENVELOPE_FILE)&.get_input_stream&.read }
      rescue Errno::ENOENT, Zip::Error
        nil
      end
      private_class_method :envelope_source

      # Encrypts the package at source_path (a .cap file, or a package
      # directory which is packed first) for the recipient's RSA public
      # key (or X.509 certificate) and writes the encrypted .cap to
      # output_path.
      def encrypt(source_path, public_key_path, output_path)
        public_key = load_public_key(public_key_path)
        with_cap_file(source_path) do |cap_path|
          envelope, ciphertext = encrypt_bytes(File.binread(cap_path), public_key)
          write_encrypted_cap(output_path, read_source(cap_path, Package::METADATA_FILE),
                              envelope, ciphertext)
        end
        output_path
      end

      # Decrypts the encrypted package at encrypted_path (.cap file or
      # uncompressed directory) with the recipient's RSA private key and
      # writes the plaintext .cap to output_path.
      def decrypt(encrypted_path, private_key_path, output_path)
        private_key = load_private_key(private_key_path)
        envelope = load_envelope(encrypted_path)
        ciphertext = read_source(encrypted_path, ENCRYPTED_FILE)
        File.binwrite(output_path, decrypt_bytes(ciphertext, envelope, private_key))
        output_path
      end

      # Decrypts an encrypted package into a fresh temporary directory
      # and returns the directory path. The cipher is selected from the
      # envelope's keyManagement (for_encrypted), so
      # Package.new(decryption_key:) accepts either key format
      # transparently.
      def self.decrypt_to_directory(source_path, private_key_path)
        Dir.mktmpdir.tap do |tmp|
          inner_cap = File.join(tmp, "inner.cap")
          for_encrypted(source_path).decrypt(source_path, private_key_path, inner_cap)
          package_path = File.join(tmp, File.basename(source_path.to_s, ".cap"))
          FileUtils.mkdir_p(package_path)
          Packager.new.unpack(inner_cap, package_path)
          FileUtils.rm_f(inner_cap)
          return package_path
        end
      end

      private

      def with_cap_file(source_path)
        return yield source_path if File.file?(source_path) && File.extname(source_path) == ".cap"
        raise CipherError, "cannot encrypt: #{source_path}" unless File.directory?(source_path)

        Dir.mktmpdir do |dir|
          cap_path = File.join(dir, "inner.cap")
          Packager.new.compress_package(Capsium::Package.new(source_path), cap_path)
          yield cap_path
        end
      end

      def encrypt_bytes(plaintext, public_key)
        cipher = OpenSSL::Cipher.new(ALGORITHM.downcase)
        cipher.encrypt
        dek = cipher.random_key
        gcm_iv = cipher.random_iv
        ciphertext = cipher.update(plaintext) + cipher.final
        [envelope_for(dek, gcm_iv, cipher.auth_tag, public_key), ciphertext]
      end

      # The encryption envelope carrying the DEK protected for the
      # recipient (RSA-OAEP-SHA256 wrapped here; OpenPgpCipher overrides
      # this with an OpenPGP message). The subclass seam for key
      # management; ALGORITHM/iv/authTag stay as-is.
      def envelope_for(dek, gcm_iv, auth_tag, public_key)
        EncryptionConfig.new(
          encryption: EncryptionEnvelope.new(
            algorithm: ALGORITHM, key_management: KEY_MANAGEMENT,
            encrypted_dek: Base64.strict_encode64(public_key.encrypt(dek, RSA_OPTIONS)),
            iv: Base64.strict_encode64(gcm_iv), auth_tag: Base64.strict_encode64(auth_tag)
          )
        )
      end

      def decrypt_bytes(ciphertext, envelope, private_key)
        dek = unwrap_dek(envelope, private_key)
        gcm_decrypt(ciphertext, dek, envelope)
      rescue ArgumentError
        raise CipherError, "invalid Base64 in the encryption envelope"
      end

      # Recovers the DEK from the envelope (RSA-OAEP-SHA256 unwrap here;
      # OpenPgpCipher overrides this with an OpenPGP decryption).
      def unwrap_dek(envelope, private_key)
        private_key.decrypt(Base64.strict_decode64(envelope.encrypted_dek), RSA_OPTIONS)
      rescue OpenSSL::PKey::PKeyError
        # DEK unwrap failure (wrong key or a malformed envelope).
        raise DecryptionError, "decryption failed: wrong key or tampered package"
      end

      def gcm_decrypt(ciphertext, dek, envelope)
        cipher = OpenSSL::Cipher.new(ALGORITHM.downcase)
        cipher.decrypt
        cipher.key = dek
        cipher.iv = Base64.strict_decode64(envelope.iv)
        cipher.auth_tag = Base64.strict_decode64(envelope.auth_tag)
        cipher.update(ciphertext) + cipher.final
      rescue OpenSSL::Cipher::CipherError
        # GCM tag verification failure (wrong key or tampered
        # ciphertext), or a malformed envelope iv/authTag.
        raise DecryptionError, "decryption failed: wrong key or tampered package"
      end

      def write_encrypted_cap(output_path, metadata_json, envelope, ciphertext)
        FileUtils.rm_f(output_path)
        Zip::File.open(output_path, create: true) do |zip|
          zip.get_output_stream(Package::METADATA_FILE) { |stream| stream.write(metadata_json) }
          zip.get_output_stream(ENVELOPE_FILE) { |stream| stream.write(envelope.to_json) }
          zip.get_output_stream(ENCRYPTED_FILE) { |stream| stream.write(ciphertext) }
        end
      end

      def load_envelope(encrypted_path)
        envelope = EncryptionConfig.from_json(read_source(encrypted_path, ENVELOPE_FILE)).encryption
        return envelope if envelope && supported_envelope?(envelope)

        raise CipherError, "missing or unsupported encryption envelope in: #{encrypted_path}"
      rescue Lutaml::Model::Error, JSON::ParserError => e
        raise CipherError, "invalid encryption envelope in #{encrypted_path}: #{e.message}"
      end

      def supported_envelope?(envelope)
        # self.class:: so subclasses (OpenPgpCipher) match their own
        # KEY_MANAGEMENT despite Ruby's lexical constant lookup.
        [envelope.algorithm, envelope.key_management] == [ALGORITHM, self.class::KEY_MANAGEMENT]
      end

      def read_source(path, entry_name)
        return File.binread(File.join(path, entry_name)) if File.directory?(path)

        Zip::File.open(path) do |zip|
          entry = zip.find_entry(entry_name)
          raise CipherError, "entry missing in #{path}: #{entry_name}" unless entry

          return entry.get_input_stream.read
        end
      rescue Errno::ENOENT, Zip::Error => e
        raise CipherError, "cannot read #{entry_name} in #{path}: #{e.message}"
      end

      def load_public_key(public_key_path)
        pem = File.read(public_key_path)
        OpenSSL::PKey::RSA.new(pem)
      rescue OpenSSL::PKey::PKeyError
        OpenSSL::X509::Certificate.new(pem).public_key
      rescue OpenSSL::X509::CertificateError, Errno::ENOENT
        raise CipherError, "cannot load public key or certificate: #{public_key_path}"
      end

      def load_private_key(private_key_path)
        OpenSSL::PKey::RSA.new(File.read(private_key_path))
      rescue OpenSSL::PKey::PKeyError, Errno::ENOENT
        raise CipherError, "cannot load private key: #{private_key_path}"
      end
    end
  end
end
