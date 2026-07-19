# Changelog

## 0.3.0

### Added

- Digital signatures (RSA-SHA256, X.509) per the packaging and security
  standard clauses: `Capsium::Package::Signer` signs a package directory in
  place (`signature.sig` plus the embedded public key PEM, recorded as
  `security.digitalSignatures {publicKey, signatureFile}` in
  `security.json`) and verifies declared signatures. The signed payload is
  the concatenation, in sorted package-relative path order, of the raw
  bytes of every checksum-covered file (everything except `security.json`
  and `signature.sig`) — verifiable independently with
  `openssl dgst -sha256 -verify`.
- Signed packages are verified automatically on load:
  `Capsium::Package#verify_signature`/`#verify_signature!`/`#signed?`;
  a mismatch raises `Capsium::Package::Signer::SignatureMismatchError`,
  so the reactor refuses to serve tampered signed packages.
- `capsium package sign PATH --key KEY.pem [--cert CERT.pem]` and
  `capsium package verify-signature PATH [--cert CERT.pem]` (exit status 1
  on unsigned packages and verification failures). Both accept a package
  directory or a `.cap` file.
- Whole-package encryption (AES-256-GCM, RSA-OAEP-SHA256 wrapped DEK) per
  the packaging standard's encryption clause: `Capsium::Package::Cipher`
  encrypts a package directory or `.cap` into the standard encrypted
  layout (`metadata.json` cleartext, `signature.json` encryption envelope,
  `package.enc` AES-256-GCM of the inner `.cap` zip) and decrypts it back.
  The OCB/OpenPGP alternatives mentioned by the standard are intentionally
  not implemented.
- `capsium package encrypt PATH --public-key PUB.pem -o OUT.cap` and
  `capsium package decrypt PATH --private-key PRIV.pem [-o OUT.cap]`.
- `Capsium::Package.new(path, decryption_key:)` transparently decrypts an
  encrypted `.cap` (or uncompressed encrypted directory) on load; without
  a key it raises `Capsium::Package::Cipher::KeyRequiredError` (the
  reactor refuses to serve), and a wrong key or tampered ciphertext raises
  `Capsium::Package::Cipher::DecryptionError` (GCM authentication).
- `Capsium::Packager#transform_cap`/`#with_unpacked_cap` helpers for
  in-place `.cap` transformations.

### Changed

- Integrity checksums now exclude `signature.sig` in addition to
  `security.json` (the signature signs the checksum-covered payload, so it
  cannot be part of it).
- `capsium package pack` drops signing artifacts (`signature.sig`,
  embedded public key) when repacking: signing is a post-pack step.

## 0.2.0

### Changed

- Migrated all package configuration models from shale to lutaml-model.
- All configuration files now follow the canonical schemas
  (ARCHITECTURE.md sections 2-6):
  - `metadata.json`: `dependencies` is an object of `guid -> semver range`;
    `name`/`version`/`description`/`guid`/`uuid` are the required fields.
  - `manifest.json`: a `resources` object keyed by package-relative path
    (`type`, `visibility`, optional `version`).
  - `routes.json`: optional top-level `index` plus a `routes` array with
    discriminated kinds (`resource` / `dataset` / handler).
  - `storage.json`: `storage.dataSets` object; dataset `source` and
    `schemaFile` are package-relative paths.
- Legacy (pre-0.2) configuration files are accepted on read and normalized
  to the canonical forms; writers emit only the canonical forms.
- Manifest and routes auto-generation is deterministic (sorted); HTML files
  get dual routes, the index HTML gets `/`, datasets get
  `/api/v1/data/<id>`.
- The reactor serves dataset routes as JSON, sets `Cache-Control: public,
  max-age=31536000` on static resources (configurable), responds 501 to
  handler routes, and rejects packages that fail integrity verification.
- The CLI exits nonzero on errors.

### Added

- `security.json` with SHA-256 checksums over every package file, generated
  at pack time; verified automatically on load (`Package#verify_integrity`,
  `Capsium::Package::Security::IntegrityError` on mismatch).
- `capsium package validate <path|cap>`: per-check validation report
  (metadata formats, on-disk existence of manifest resources, route targets
  and dataset sources, dataset JSON-schema validation, checksums, external
  http(s) references in content), exit status 1 on any failure.
- `capsium package unpack <cap> [-o dir]`.
- `Capsium::Package::Validator` and `Capsium::Package::Security`.
- Reactor introspection HTTP API (ARCHITECTURE.md section 7):
  `GET /api/v1/introspect/metadata`, `/routes`, `/content-hashes` and
  `/content-validity`, served as JSON by `Capsium::Reactor::Introspection`.
  `content-hashes` is the SHA-256 of the `.cap` blob, or of the canonical
  JSON serialization of the content checksums for directory sources;
  `content-validity` re-verifies integrity live.
- Zip-slip protection on `.cap` extraction: entries escaping the
  destination (absolute paths, drive letters, `..` segments) raise
  `Capsium::Packager::UnsafeEntryError`.
- RBS signatures for the public API (`sig/`), kept green by the
  `rbs:validate` rake task (part of the default rake task).
- `Capsium::Package#cap_file_path`.

### Removed

- `Capsium::Protector` (bit-rotted, insecure; encryption/signing is
  deferred to a later phase).
- shale dependency (replaced by lutaml-model); base64 dependency.
- Unused constants `Package::PACKAGING_FILE`, `Package::SIGNATURE_FILE`,
  `Package::ENCRYPTED_PACKAGING_FILE`, `Routes::DEFAULT_INDEX_TARGET`.
