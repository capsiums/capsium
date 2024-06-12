# frozen_string_literal: true

# lib/capsium/protector.rb
require "openssl"
require "base64"
require "json"

module Capsium
  class Protector
    def initialize(package, encryption_metadata = nil,
digital_signature_metadata = nil)
      @package = package
      @encryption_metadata = encryption_metadata
      @digital_signature_metadata = digital_signature_metadata
    end

    def apply_encryption_and_sign
      encrypted_file = apply_encryption if @encryption_metadata
      sign_package(encrypted_file) if @digital_signature_metadata
    end

    def verify_signature
      signature_data = JSON.parse(File.read(signature_file_path))
      public_key = OpenSSL::PKey::RSA.new(File.read(public_key_path))
      digest = OpenSSL::Digest.new(signature_data["algorithm"])
      data = combined_data
      signature = Base64.decode64(signature_data["signature"])

      public_key.verify(digest, signature, data)
    end

    private

    def apply_encryption
      encryption = @encryption_metadata
      data = File.read(File.join(@package.path,
                                 Package::ENCRYPTED_PACKAGING_FILE))
      cipher = OpenSSL::Cipher.new(encryption[:algorithm])
      cipher.encrypt
      key = cipher.random_key
      iv = cipher.random_iv

      encrypted_data = cipher.update(data) + cipher.final
      encrypted_file = File.join(@package.path, "#{@package.name}.enc")

      File.open(encrypted_file, "wb") do |f|
        f.write(iv)
        f.write(encrypted_data)
      end

      save_encryption_key(key, encryption[:keyManagement])
      encrypted_file
    end

    def save_encryption_key(key, key_management)
      case key_management
      when "secure"
        # Implement secure key storage mechanism
        File.write(File.join(@package.path, "encryption_key.secure"),
                   Base64.encode64(key))
      else
        raise "Unknown key management strategy: #{key_management}"
      end
    end

    def sign_package(encrypted_file)
      key = OpenSSL::PKey::RSA.new(@digital_signature_metadata[:keyLength])
      data = combined_data(encrypted_file)
      digest = OpenSSL::Digest.new(@digital_signature_metadata[:algorithm])
      signature_data = key.sign(digest, data)

      signature_json = {
        algorithm: @digital_signature_metadata[:algorithm],
        certificateType: @digital_signature_metadata[:certificateType],
        signature: Base64.encode64(signature_data),
      }

      File.write(signature_file_path, JSON.pretty_generate(signature_json))
      File.write(public_key_path, key.public_key.to_pem)
    end

    def combined_data(encrypted_file = nil)
      metadata_content = File.read(File.join(@package.path,
                                             Package::METADATA_FILE))
      signature_content = File.read(signature_file_path).sub(
        /"signature": ".*"/, '"signature": ""'
      )
      package_enc_content = File.read(encrypted_file || File.join(
        @package.path, "#{@package.name}.enc"
      ))

      metadata_content + signature_content + package_enc_content
    end

    def signature_file_path
      File.join(@package.path, @digital_signature_metadata[:signatureFile])
    end

    def public_key_path
      File.join(@package.path, "public_key.pem")
    end
  end
end
