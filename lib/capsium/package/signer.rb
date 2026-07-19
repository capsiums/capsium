# frozen_string_literal: true

require "openssl"

module Capsium
  class Package
    # Signs and verifies Capsium packages with RSA-SHA256 digital
    # signatures (05x-packaging "Digital Signature Using X.509",
    # 05x-security "Digital Signatures").
    #
    # Signed payload construction (deterministic, openssl-verifiable): the
    # concatenation, in sorted package-relative path order, of the raw
    # bytes of every file covered by the security.json integrity checksums
    # — i.e. every package file except security.json and signature.sig.
    # The signature itself is the raw RSA-SHA256 signature over that
    # payload, stored in signature.sig. Equivalent openssl verification:
    #
    #   openssl dgst -sha256 -verify pubkey.pem -signature signature.sig payload.bin
    #
    # where payload.bin is the concatenation described above.
    class Signer
      ALGORITHM = "RSA-SHA256"
      MIN_KEY_BITS = 2048

      # Package-relative name of the embedded public key PEM recorded in
      # security.json digitalSignatures.publicKey.
      PUBLIC_KEY_FILE = "signature.pub.pem"

      # Structural problems: no signature declared, missing signature or
      # key files, unloadable keys, checksum-covered files missing.
      class SignatureError < Capsium::Error; end

      # A signature is declared but does not match the package contents.
      class SignatureMismatchError < SignatureError; end

      # Signature operations requested on a package whose security.json
      # declares no digitalSignatures.
      class UnsignedPackageError < SignatureError; end

      attr_reader :package_path

      def initialize(package_path)
        @package_path = package_path
      end

      # Signs the package directory in place: embeds the public key PEM,
      # regenerates security.json (checksums plus digitalSignatures) and
      # writes the raw RSA-SHA256 signature to signature.sig. When a
      # certificate is given it must match the private key, and the
      # certificate's public key is embedded instead.
      def sign(private_key_path, certificate_path = nil)
        private_key = load_private_key(private_key_path)
        File.write(public_key_path, public_pem_for(private_key, certificate_path))
        security = Security.generate(@package_path, digital_signatures: digital_signatures)
        security.save_to_file
        File.binwrite(signature_path, private_key.sign("SHA256", payload(security)))
        signature_path
      end

      # True when the declared signature verifies against the payload.
      # Without an explicit key path, the embedded public key is used.
      # Raises typed SignatureError subclasses on structural problems.
      def verify(public_key_path = nil)
        signature = read_signature
        data = payload(declared_security)
        public_key(public_key_path).verify("SHA256", signature, data)
      rescue OpenSSL::PKey::PKeyError
        false
      end

      def verify!(public_key_path = nil)
        return true if verify(public_key_path)

        raise SignatureMismatchError,
              "digital signature does not match the package contents"
      end

      def signed?
        declared_security.signed?
      end

      private

      def declared_security
        Security.new(File.join(@package_path, Package::SECURITY_FILE))
      end

      def digital_signatures
        DigitalSignatures.new(public_key: PUBLIC_KEY_FILE, signature_file: Package::SIGNATURE_FILE)
      end

      # The canonical signed payload: the concatenation, in sorted
      # package-relative path order, of the bytes of every file covered by
      # the integrity checksums.
      def payload(security)
        security.checksums.keys.sort.map do |relative_path|
          file_path = File.join(@package_path, relative_path)
          unless File.file?(file_path)
            raise SignatureError, "file covered by checksums is missing: #{relative_path}"
          end

          File.binread(file_path)
        end.join
      end

      def read_signature
        unless signed?
          raise UnsignedPackageError,
                "package is not signed (security.json declares no digitalSignatures)"
        end
        return File.binread(signature_path) if File.file?(signature_path)

        raise SignatureError, "signature file missing: #{signature_file_name}"
      end

      def signature_file_name
        declared_security.digital_signatures.signature_file || Package::SIGNATURE_FILE
      end

      def signature_path
        File.join(@package_path, signature_file_name)
      end

      def public_key_path
        File.join(@package_path, PUBLIC_KEY_FILE)
      end

      def public_key(public_key_path)
        pem, source = public_key_pem(public_key_path)
        OpenSSL::PKey::RSA.new(pem)
      rescue OpenSSL::PKey::PKeyError
        certificate_public_key(pem, source)
      end

      def public_key_pem(public_key_path)
        return [File.read(public_key_path), public_key_path] if public_key_path

        embedded = declared_security.digital_signatures&.public_key || PUBLIC_KEY_FILE
        embedded_path = File.join(@package_path, embedded)
        return [File.read(embedded_path), embedded] if File.file?(embedded_path)

        raise SignatureError, "public key file missing: #{embedded}"
      end

      def certificate_public_key(pem, source)
        OpenSSL::X509::Certificate.new(pem).public_key
      rescue OpenSSL::X509::CertificateError
        raise SignatureError, "cannot load public key or certificate: #{source}"
      end

      def load_private_key(private_key_path)
        key = OpenSSL::PKey::RSA.new(File.read(private_key_path))
        return key if key.n.num_bits >= MIN_KEY_BITS

        raise SignatureError, "RSA key too short: minimum #{MIN_KEY_BITS} bits required"
      rescue OpenSSL::PKey::PKeyError, Errno::ENOENT
        raise SignatureError, "cannot load private key: #{private_key_path}"
      end

      def public_pem_for(private_key, certificate_path)
        return private_key.public_key.to_pem unless certificate_path

        certificate = load_certificate(certificate_path)
        unless certificate.check_private_key(private_key)
          raise SignatureError, "certificate does not match the private key: #{certificate_path}"
        end

        certificate.public_key.to_pem
      end

      def load_certificate(certificate_path)
        OpenSSL::X509::Certificate.new(File.read(certificate_path))
      rescue OpenSSL::X509::CertificateError, Errno::ENOENT
        raise SignatureError, "cannot load certificate: #{certificate_path}"
      end
    end
  end
end
