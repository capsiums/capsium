# frozen_string_literal: true

module Capsium
  class Package
    # OpenPGP support (signatures per ARCHITECTURE.md section 6a and
    # encryption per section 6b) through the rnp gem's binding to
    # librnp.
    #
    # rnp is a soft dependency: it is only required when an OpenPGP
    # feature is actually used, and this module is the single place that
    # loads it. When the rnp gem or the librnp shared library cannot be
    # loaded, the entry points raise OpenPgpUnavailableError with
    # installation guidance.
    module OpenPgp
      # The rnp gem or the librnp shared library is not available.
      class OpenPgpUnavailableError < Capsium::Error; end

      # A key file is unreadable or holds no suitable OpenPGP key.
      class KeyError < Capsium::Error; end

      UNAVAILABLE_MESSAGE =
        "OpenPGP support requires librnp and the rnp gem " \
        "(e.g. `brew install rnp` and `gem install rnp`)"

      # One loaded key file: the Rnp context holding the key material
      # and the selected key within it.
      LoadedKey = Data.define(:rnp, :key)

      # A fresh Rnp context. Raises OpenPgpUnavailableError when the rnp
      # gem or librnp cannot be loaded.
      def self.rnp
        require "rnp"
        Rnp.new
      rescue LoadError
        raise OpenPgpUnavailableError, UNAVAILABLE_MESSAGE
      end

      # Loads the OpenPGP key at key_path (armored or binary, public or
      # secret — the format is auto-detected) into a fresh Rnp context.
      # With secret: true the selected key must hold secret key material
      # (signing, decryption); otherwise any loaded key is selected
      # (verification, encryption). Raises KeyError when the file is
      # unreadable or holds no suitable key.
      def self.load_key(key_path, secret: false)
        instance = rnp
        instance.load_keys(input: Rnp::Input.from_string(File.binread(key_path)),
                           format: "GPG")
        key = select_key(instance, secret: secret)
        return LoadedKey.new(rnp: instance, key: key) if key

        raise KeyError, "no suitable #{secret ? 'secret' : 'public'} OpenPGP key in: #{key_path}"
      rescue Errno::ENOENT, Rnp::Error
        raise KeyError, "cannot load OpenPGP key: #{key_path}"
      end

      def self.select_key(instance, secret:)
        keys = instance.keyids.map { |keyid| instance.find_key(keyid: keyid) }
        return keys.find(&:secret_key_present?) if secret

        keys.first
      end
      private_class_method :select_key
    end
  end
end
