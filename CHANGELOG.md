# Changelog

## 0.4.0

### Added

- Static registries (ARCHITECTURE.md section 4a follow-on): a registry
  is a directory or a static https base URL holding an `index.json`
  (`packages` -> GUID -> `name` + `versions` -> version -> `file`,
  `sha256`, `size`) with `.cap` files stored relative to the registry
  root, so any static host (GitHub Pages, S3, nginx) can serve one.
  `Capsium::Registry.fetch(ref)` returns `Registry::Local` (read-write
  directory) or `Registry::Remote` (read-only https base URL over
  net/http with redirect following and timeouts; plain http for
  loopback hosts only). `Registry#resolve` picks the newest version
  satisfying a semver constraint via the built-in
  `Version`/`VersionRange` matcher.
- `Registry::Local#push`: validates the `.cap` with
  `Capsium::Package::Validator` (`Registry::InvalidPackageError` on
  failure), copies it into the registry directory and atomically
  rewrites `index.json` (tmp + rename) with recomputed sha256 and size.
- `Registry#install`: fetches the resolved `.cap`, verifies it against
  the sha256 declared in the index (`Registry::ChecksumMismatchError`
  on mismatch) and installs it into the package store as
  `<name>-<version>.cap`, atomically updating the store's own
  `index.json` (`Package::Store#install`). All registry failures are
  typed `Registry::RegistryError` subclasses
  (`RegistryNotConfiguredError`, `InvalidRegistryError`,
  `InvalidPackageError`, `PackageNotFoundError`,
  `UnsatisfiableConstraintError`, `ChecksumMismatchError`,
  `FetchError`).
- `capsium package push PACKAGE --registry DIR` and
  `capsium install GUID [--constraint RANGE] [--registry DIR_OR_URL]
  [--store DIR]`; the registry defaults to `CAPSIUM_REGISTRY`, the
  store to `CAPSIUM_STORE` (typed errors when unconfigured).
- `capsium reactor serve capsium://GUID` (install-then-serve with
  `--registry`/`--store`/`--constraint`), and dependency-resolution
  fallback for composite packages: `Package::DependencyResolver` (and
  `Capsium::Package.new`/`Capsium::Reactor.new` through their new
  `registry:` keyword) installs a dependency from the configured
  registry when the store has no package for its GUID — fallback chain
  store -> registry -> typed error (`DependencyNotFoundError` /
  `UnsatisfiableDependencyError`).

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
- The Capsium package testing YAML DSL (05x-testing): packages declare
  tests in `tests/*.yaml` files (top-level `tests` list), and
  `capsium package test PATH` runs them with per-test `PASS`/`FAIL`
  output, a summary line and proper exit codes. Supported test types:
  `route` (expected status, optional `response_contains` and
  `expected_content_type` against a reactor started for the run),
  `file` (existence, optional `contains`), `data_validation` (dataset
  rows validated against a JSON schema, JSON and YAML formats) and
  `config` (configuration files parsed and the known package configs
  validated against their canonical models). Implemented as an
  open/closed registry of `Capsium::Package::Testing::TestCase`
  subclasses run by `Capsium::Package::Testing::TestSuite`; invalid
  test definitions are reported as failures instead of aborting the run.
- Layered storage (ARCHITECTURE.md section 5a): `storage.layers` stacks
  overlay directories over `content/` (bottom -> top in declaration
  order), each mirroring the `content/` tree.
  `Capsium::Package::MergedView` — the merged-view home shared by the
  package (validation) and the reactor (serving) — resolves content
  top-first, honors `.capsium-tombstones` deletions (a tombstoned path
  resolves 404 even when a lower layer holds the file, and a tombstone
  also suppresses dependency content below it), and hides
  `visibility: private` layers and non-exported resources in the
  exported-only view dependents get. Packages without a `layers` config
  behave exactly as before (single implicit `content/` layer).
- Composite packages (ARCHITECTURE.md section 4a):
  `metadata.dependencies` (GUID -> semver range) resolve against a
  package store (`CAPSIUM_STORE` or `--store`) of
  `<name>-<version>.cap` files plus an optional `index.json` (GUID ->
  file); the newest satisfying version wins via the built-in semver
  matcher `Capsium::Package::Version`/`VersionRange` (`>=`, `^`, `~`,
  exact, `*`, `x`-wildcards/partials, comma/space conjunctions — no new
  runtime dependency). Resolution is recursive with circularity
  detection and raises typed errors:
  `Capsium::Package::DependencyNotFoundError`,
  `UnsatisfiableDependencyError`, `CircularDependencyError`,
  `DependencyVisibilityError`.
- Resolved dependencies become read-only layers below all of the
  dependent's own layers, and only `exported` resources are visible;
  routes may address dependency content explicitly as
  `"<dependency-guid>/<path>"` and declare the route-inheritance
  attributes of 05x-routing: `remap` (replaces the serving path),
  `responseRewrite` (`body`, `headers`), `responseHeaders` (merged over
  served headers) and `requestHeaders` (parsed and exposed for
  forwarding reactors; a documented no-op for this static reactor).
  Referencing a dependency's private or missing resource is a load-time
  error. `capsium package info` prints the resolved dependency tree;
  `capsium reactor serve` accepts `--store`.
- Authentication (05x-authentication, ARCHITECTURE.md section 4b):
  `authentication.json` declares `basicAuth {enabled, passwdFile,
  realm}` and `oauth2 {enabled, provider, clientId, authorizationUrl,
  tokenUrl, userinfoUrl, redirectPath, scopes}`; the reactor enforces
  it via `Capsium::Reactor::Authenticator`. Basic authentication
  challenges (401 + `WWW-Authenticate`) and verifies against the
  htpasswd file — bcrypt via the new `bcrypt` runtime dependency, plus
  pure-Ruby md5-crypt (`$apr1$`/`$1$` as deployed by
  htpasswd/OpenSSL/glibc), `{SHA}` and a `crypt(3)` fallback.
  OAuth2 runs the authorization-code flow over net/http: `/auth/login`
  redirects with HMAC-signed state, the callback exchanges the code at
  `tokenUrl`, fetches the userinfo claims and establishes an
  HMAC-SHA256 signed session cookie (`Capsium::Reactor::Session`).
  Secrets never come from the package: `clientSecret`/`sessionSecret`
  and role assignments live in `deploy.json` (`--deploy` or
  `CAPSIUM_DEPLOY`); without a configured session secret the reactor
  generates one and persists it (mode 0600) outside the package.
  Dataset-route `accessControl {roles, authenticationRequired}` is
  enforced after authentication: 401 unauthenticated, 403 unauthorized.
- The `content-validity` introspection entry now reports `signed` and
  `encrypted` status, plus `signatureValid` when the package declares a
  signature; `Capsium::Package#encrypted?` reports whether the package
  was loaded from an encrypted source.

### Changed

- Integrity checksums now exclude `signature.sig` in addition to
  `security.json` (the signature signs the checksum-covered payload, so it
  cannot be part of it).
- `capsium package pack` drops signing artifacts (`signature.sig`,
  embedded public key) when repacking: signing is a post-pack step.
- The reactor serves resources through `Package#merged_view` (the
  overlay-aware resolution path); behavior is unchanged for packages
  without layers.
- Loading a package with declared `metadata.dependencies` now resolves
  them eagerly against the package store (`store:` or `CAPSIUM_STORE`);
  a package whose dependencies cannot resolve (including normalized
  pre-0.2 dependency declarations) fails to load with a typed error.
- `Metrics/ParameterLists` rubocop budget raised to 6 for the reactor
  constructor's per-concern keywords.

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
