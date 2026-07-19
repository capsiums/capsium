# frozen_string_literal: true

# Availability probe and shared key material for OpenPGP specs. The
# rnp gem needs the librnp shared library; when it cannot load (e.g.
# CI without librnp) the OpenPGP specs skip cleanly so the suite stays
# green.
module OpenPgpSpecHelper
  module_function

  def available?
    return @available unless @available.nil?

    require "rnp"
    Rnp.new
    @available = true
  rescue LoadError, StandardError
    @available = false
  end

  # Generates a throwaway RSA-2048 OpenPGP keypair plus a second,
  # unrelated "wrong" keypair, as armored files in dir:
  # test-secret.asc/test-public.asc and wrong-secret.asc/wrong-public.asc.
  def generate_keypairs(dir)
    rnp = Rnp.new
    write_keypair(rnp, dir, "test", "Capsium Test <capsium@example.com>")
    write_keypair(rnp, dir, "wrong", "Wrong Key <wrong@example.com>")
  end

  def write_keypair(rnp, dir, stem, userid)
    key = rnp.generate_key({ "primary" => { "type" => "RSA", "length" => 2048,
                                            "userid" => userid } })[:primary]
    File.write(File.join(dir, "#{stem}-secret.asc"), key.export_secret(armored: true))
    File.write(File.join(dir, "#{stem}-public.asc"), key.export_public(armored: true))
  end
end
