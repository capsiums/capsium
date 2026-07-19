# frozen_string_literal: true

module Capsium
  class Package
    # Signs and verifies Capsium packages with OpenPGP detached
    # signatures (ARCHITECTURE.md section 6a) through librnp
    # (Capsium::Package::OpenPgp). Parallel to the RSA-SHA256/X.509
    # Signer with the same construction semantics and the same error
    # taxonomy (Signer::SignatureError subclasses), so loaders and the
    # CLI handle both schemes uniformly.
    #
    # The signed payload is identical to the Signer's: the
    # concatenation, in sorted package-relative path order, of the raw
    # bytes of every file covered by the security.json integrity
    # checksums. signature.sig holds the armored detached OpenPGP
    # signature (SHA-256) over that payload; the signer's armored
    # public key is embedded as signature.pub.asc and security.json
    # records:
    #
    #   "digitalSignatures": { "certificateType": "OpenPGP",
    #     "publicKey": "signature.pub.asc",
    #     "signatureFile": "signature.sig" }
    #
    # Keys are OpenPGP key files (armored or binary, auto-detected);
    # signing needs a secret key, verification a public one.
    class OpenPgpSigner
      ALGORITHM = "OpenPGP"
      CERTIFICATE_TYPE = "OpenPGP"
      HASH = "SHA256"

      # Package-relative name of the embedded armored OpenPGP public key
      # recorded in security.json digitalSignatures.publicKey.
      PUBLIC_KEY_FILE = "signature.pub.asc"

      attr_reader :package_path

      def initialize(package_path)
        @package_path = package_path
      end

      # Signs a package directory in place, or a .cap file (unpacked,
      # signed, recompressed), with the OpenPGP secret key at
      # secret_key_path. Returns the signed path.
      def self.sign_package(path, secret_key_path)
        return new(path).sign(secret_key_path) unless cap?(path)

        Packager.new.transform_cap(path) { |dir| new(dir).sign(secret_key_path) }
        path
      end

      # Verifies the declared OpenPGP signature of a package directory
      # or .cap file (false on mismatch; raises typed
      # Signer::SignatureError subclasses on structural problems, e.g.
      # an unsigned package). public_key_path is an OpenPGP public key
      # file; without it the key embedded in the package is used.
      def self.verify_package(path, public_key_path = nil)
        return new(path).verify(public_key_path) unless cap?(path)

        Packager.new.with_unpacked_cap(path) { |dir| new(dir).verify(public_key_path) }
      end

      def self.cap?(path)
        File.extname(path) == ".cap"
      end
      private_class_method :cap?

      # Signs the package directory in place: embeds the armored public
      # key, regenerates security.json (checksums plus digitalSignatures
      # with certificateType "OpenPGP") and writes the armored detached
      # OpenPGP signature to signature.sig.
      def sign(secret_key_path)
        loaded = OpenPgp.load_key(secret_key_path, secret: true)
        File.write(public_key_path, loaded.key.export_public(armored: true))
        security = Security.generate(@package_path, digital_signatures: digital_signatures)
        security.save_to_file
        signature = loaded.rnp.detached_sign(
          input: Rnp::Input.from_string(payload(security)),
          signers: loaded.key, hash: HASH, armored: true
        )
        File.write(signature_path, signature)
        signature_path
      end

      # True when the declared signature verifies against the payload.
      # Without an explicit key path, the embedded public key is used.
      def verify(public_key_path = nil)
        signature = read_signature
        data = payload(declared_security)
        loaded = verification_key(public_key_path)
        signature_matches(loaded, data, signature)
      end

      def verify!(public_key_path = nil)
        return true if verify(public_key_path)

        raise Signer::SignatureMismatchError,
              "digital signature does not match the package contents"
      end

      def signed?
        declared_security.signed?
      end

      private

      # Reached only after the rnp binding loaded successfully (the
      # verification key is loaded first), so the Rnp error constants
      # are defined here.
      def signature_matches(loaded, data, signature)
        loaded.rnp.detached_verify(data: Rnp::Input.from_string(data),
                                   signature: Rnp::Input.from_string(signature))
        true
      rescue Rnp::InvalidSignatureError
        false
      end

      def declared_security
        Security.new(File.join(@package_path, Package::SECURITY_FILE))
      end

      def digital_signatures
        DigitalSignatures.new(certificate_type: CERTIFICATE_TYPE,
                              public_key: PUBLIC_KEY_FILE,
                              signature_file: Package::SIGNATURE_FILE)
      end

      # The canonical signed payload (ARCHITECTURE.md section 6a,
      # identical to Signer's): the concatenation, in sorted
      # package-relative path order, of the bytes of every file covered
      # by the integrity checksums.
      def payload(security)
        security.checksums.keys.sort.map do |relative_path|
          file_path = File.join(@package_path, relative_path)
          unless File.file?(file_path)
            raise Signer::SignatureError,
                  "file covered by checksums is missing: #{relative_path}"
          end

          File.binread(file_path)
        end.join
      end

      def read_signature
        unless signed?
          raise Signer::UnsignedPackageError,
                "package is not signed (security.json declares no digitalSignatures)"
        end
        return File.binread(signature_path) if File.file?(signature_path)

        raise Signer::SignatureError, "signature file missing: #{signature_file_name}"
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

      def verification_key(public_key_path)
        return OpenPgp.load_key(public_key_path) if public_key_path

        embedded = declared_security.digital_signatures&.public_key || PUBLIC_KEY_FILE
        embedded_path = File.join(@package_path, embedded)
        return OpenPgp.load_key(embedded_path) if File.file?(embedded_path)

        raise Signer::SignatureError, "public key file missing: #{embedded}"
      end
    end
  end
end
