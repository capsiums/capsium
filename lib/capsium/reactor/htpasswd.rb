# frozen_string_literal: true

require "base64"
require "bcrypt"
require "digest"
require "openssl"

module Capsium
  class Reactor
    # Apache htpasswd verification (05x-authentication). Supported hash
    # formats:
    # - bcrypt ($2a$/$2b$/$2y$, `htpasswd -B`) via the bcrypt gem
    # - Apache apr1 MD5 ($apr1$, `htpasswd -m`) and md5-crypt ($1$),
    #   pure-Ruby md5-crypt
    # - unsalted SHA-1 ({SHA}, `htpasswd -s`)
    # - anything else (DES, $5$/$6$) via the platform's crypt(3) —
    #   support depends on the OS
    class Htpasswd
      # md5-crypt as deployed by Apache htpasswd, OpenSSL and glibc
      # ($1$ and $apr1$ magics; identical except for the magic string).
      # NOTE: Poul-Henning Kamp's original FreeBSD implementation mixed
      # the magic in at the % 7 step where all deployed implementations
      # mix in the password (see apr_md5.c, glibc crypt-md5.c).
      module Md5Crypt
        ITOA64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        DIGEST_GROUPS = [[0, 6, 12], [1, 7, 13], [2, 8, 14], [3, 9, 15], [4, 10, 5]].freeze

        def self.verify(hash, password)
          _prefix, magic, salt, = hash.split("$", 4)
          return false if salt.nil? || salt.empty?

          Reactor.secure_compare(digest(password, salt, "$#{magic}$"), hash)
        end

        def self.digest(password, salt, magic)
          final = initial_digest(password, salt, magic)
          1000.times do |i|
            final = stretch_digest(i, password, salt, final)
          end
          "#{magic}#{salt}$#{to64(final)}"
        end

        def self.initial_digest(password, salt, magic)
          inner = Digest::MD5.digest(password + salt + password)
          context = Digest::MD5.new
          context << password << magic << salt
          length = password.length
          while length.positive?
            context << inner[0, [16, length].min]
            length -= 16
          end
          length = password.length
          while length.positive?
            context << (length.odd? ? "\0" : password[0])
            length >>= 1
          end
          context.digest
        end

        def self.stretch_digest(iteration, password, salt, final)
          context = Digest::MD5.new
          context << (iteration.odd? ? password : final)
          context << salt unless (iteration % 3).zero?
          context << password unless (iteration % 7).zero?
          context << (iteration.odd? ? final : password)
          context.digest
        end

        # The custom base-64 of md5-crypt: digest triples permuted, first
        # index to the high bits, 22 characters total.
        def self.to64(final)
          encoded = +""
          DIGEST_GROUPS.each do |a, b, c|
            value = final[c].ord | (final[b].ord << 8) | (final[a].ord << 16)
            4.times do
              encoded << ITOA64[value & 0x3f]
              value >>= 6
            end
          end
          value = final[11].ord
          2.times do
            encoded << ITOA64[value & 0x3f]
            value >>= 6
          end
          encoded
        end
      end

      attr_reader :path

      def initialize(path)
        raise Error, "htpasswd file not found: #{path}" unless File.file?(path)

        @path = path
        @entries = parse(path)
      end

      def usernames
        @entries.keys
      end

      def verify?(username, password)
        hash = @entries[username]
        return false unless hash

        verify_hash(hash, password)
      end

      private

      def parse(path)
        File.readlines(path, chomp: true).each_with_object({}) do |line, entries|
          next if line.strip.empty? || line.start_with?("#")

          username, hash = line.split(":", 2)
          entries[username] = hash
        end
      end

      def verify_hash(hash, password)
        case hash
        when /\A\$2[aby]\$/ then verify_bcrypt(hash, password)
        when /\A\$(?:apr1|1)\$/ then Md5Crypt.verify(hash, password)
        when /\A\{SHA\}/ then verify_sha1(hash, password)
        else verify_crypt(hash, password)
        end
      end

      # The bcrypt gem predates htpasswd's $2y$ tag; the variants are
      # algorithmically identical, normalized here.
      def verify_bcrypt(hash, password)
        BCrypt::Password.new(hash.sub(/\A\$2y\$/, "$2a$")) == password
      rescue BCrypt::Errors::InvalidHash
        false
      end

      def verify_sha1(hash, password)
        digest = "{SHA}#{Base64.strict_encode64(Digest::SHA1.digest(password))}"
        Reactor.secure_compare(digest, hash)
      end

      def verify_crypt(hash, password)
        computed = password.crypt(hash)
        computed && Reactor.secure_compare(computed, hash)
      end
    end

    # Constant-time string comparison (length-check first).
    def self.secure_compare(own, theirs)
      own.bytesize == theirs.bytesize &&
        OpenSSL.fixed_length_secure_compare(own, theirs)
    end
  end
end
