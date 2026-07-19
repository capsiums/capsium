# Changelog

## 0.6.0

### Added

- OpenPGP signatures and encryption through librnp (new `rnp` gem
  dependency, loaded lazily — a typed
  `Capsium::Package::OpenPgp::OpenPgpUnavailableError` with
  installation guidance is raised when the gem or librnp is missing):
  - `Capsium::Package::OpenPgpSigner` (parallel to the RSA-SHA256/X.509
    `Signer`, same construction semantics and `Signer::SignatureError`
    taxonomy): `capsium package sign PATH --openpgp --key SEC.asc`
    writes an armored detached OpenPGP signature (SHA-256) over the
    canonical section-6a payload to `signature.sig`, embeds the armored
    public key as `signature.pub.asc` and records
    `"digitalSignatures": {"certificateType": "OpenPGP", ...}` in
    security.json. Verification auto-detects the scheme from
    `certificateType` (`Signer.verify_package`,
    `Package#verify_signature`, the load-time signature gate and
    `capsium package verify-signature` all dispatch); `--openpgp
    --cert PUB.asc` verifies with an explicit OpenPGP public key.
  - `Capsium::Package::OpenPgpCipher < Cipher` (same encrypted .cap
    layout and AES-256-GCM content encryption): `capsium package
    encrypt PATH --openpgp --recipient PUB.asc -o OUT.cap` protects the
    DEK as an armored OpenPGP message
    (`signature.json`: `{"encryption": {"algorithm": "AES-256-GCM",
    "keyManagement": "OpenPGP", "message", "iv", "authTag"}}`).
    Decryption auto-detects the key management from the envelope
    (`Cipher.for_encrypted`, `Cipher.key_management`), and
    `Package.new(decryption_key:)` accepts OpenPGP secret keys
    (armored or binary) transparently. `Cipher`'s envelope/DEK handling
    was refactored into subclass seams; the RSA-OAEP-SHA256 path is
    unchanged.
  - `Capsium::Package::OpenPgp` is the single lazy loader of the rnp
    binding and the key-file loader (armor/format auto-detection,
    `OpenPgp::KeyError` for unreadable or unsuitable keys).
  - The OpenPGP specs skip cleanly when librnp cannot load, so CI
    without librnp stays green; see README "OpenPGP support (librnp)".
- Encapsulated packages (bundled dependencies): `capsium package pack
  --bundle-deps` (alias `--bundle`; `Packager#pack` option
  `bundle_deps: true`) resolves every declared `metadata.dependencies`
  entry through the store -> registry chain and embeds the resolved
  `.cap` files inside the parent under `packages/`, producing a fully
  self-contained package that activates with no store or registry. The
  `packages/index.json` manifest maps each dependency GUID to its
  embedded file, resolved version and SHA-256
  (`Capsium::Package::Bundle`). Loading resolves bundled dependencies
  FIRST — including from inside a parent `.cap` — before the store ->
  registry chain, and passes the bundle down so re-declared transitive
  dependencies resolve from it (one-level bundling policy: the parent's
  `metadata.dependencies` must list the transitive closure). The
  manifest SHA-256 is re-verified at resolution
  (`Security::IntegrityError` on mismatch) and each bundled package's
  own `security.json`/signature is verified at activation. `pack`
  gained `--store`/`--registry` options; `capsium package validate`
  resolves bundled dependency layers, so fallthrough routes of
  encapsulated packages validate.

## 0.5.0

### Added

- Multiple mounted packages per reactor: `capsium reactor serve`
  accepts multiple sources — positional arguments, repeatable
  `--mount PATH=SOURCE` options and/or a JSON mount config
  (`--config FILE`: `{"mounts": [{"path", "source", "store"?}]}`).
  Default mount points: the first source at `/`, each additional one at
  `/<metadata.name>/`; duplicate prefixes raise
  `Capsium::Reactor::MountConflictError`. Requests dispatch by
  longest-prefix mount matching (`Capsium::Reactor::Mount`); the
  `/api/v1/introspect/*` endpoints aggregate ALL mounted packages,
  `/package/<name>/{status,metadata,logs}` resolve by package name
  (404 for unknown names), metrics/logs stay reactor-global, and
  `Capsium::Reactor#cleanup` cleans up every mounted package.
  Single-source invocation is unchanged.
- Writable packages (ARCHITECTURE.md section 5a): a mounted package
  whose metadata does not declare `"readOnly": true` gets an
  append-only overlay layer in the reactor workdir (`--workdir DIR`,
  default a temporary directory removed on cleanup), always the
  topmost layer of the merged view (`MergedView` gained
  `extra_layers`). The immutable base never changes on disk and every
  write is visible on the next request (hot-swap); overlay state
  (content files, `.capsium-tombstones`, per-dataset JSON operation
  logs) persists in the workdir.
- REST CRUD over datasets (`Capsium::Reactor::DataApi`):
  `POST /api/v1/data/<dataset>` appends an item (201 + Location +
  stored item; id convention is the `id` field else the 1-based index
  as a string), `GET /<id>` reads one item, `PUT /<id>` replaces and
  `DELETE /<id>` deletes. Statuses: 400 for malformed JSON, 403 with a
  clear body on read-only packages, 404 for unknown datasets/items,
  405 for wrong verbs, 409 for duplicate/mismatched ids, 422 with the
  schema errors when the candidate document violates the dataset's
  JSON schema, 501 for SQLite datasets. Undeclared datasets are not
  served and route-level `accessControl` still applies.
- Content writes (`Capsium::Reactor::ContentApi`): `PUT <route>`
  creates/overwrites a content file (creating its route on demand;
  text bodies only for v1) and `DELETE <route>` records a tombstone so
  the path 404s even when a lower layer holds the file (404 when
  nothing to delete).
- GraphQL (new `graphql` dependency): every mounted package with
  datasets answers `<mount>/graphql` (POST, or GET with `?query=`)
  with a schema auto-derived from the package's storage
  (`Capsium::Reactor::GraphqlSchema`): a query field `<dataset>`
  (list) with an optional `id:` argument (single item) plus
  `create<Dataset>`/`update<Dataset>`/`delete<Dataset>` mutations
  matching the REST semantics including schema validation. Item types
  are inferred from the dataset's JSON schema when present, else map
  to a permissive JSON scalar; SQLite datasets are skipped. Not-found
  items, schema violations, duplicates and read-only mutations land in
  the `errors` array (no 500s on user error).
- Save composite: `POST /package/<name>/save`
  (`Capsium::Reactor::PackageSaver`) folds the base package plus its
  overlay into a NEW versioned `.cap` (`<name>-<version+patch>.cap`)
  in the workdir — overlay content files replace, tombstones delete,
  dataset mutation logs replay into the dataset files, and manifest,
  routes and security.json are regenerated — returning the `.cap`
  path and its SHA-256. The saved package passes
  `capsium package validate`. Read-only packages get 403, unknown
  names 404, non-POST 405.

### Changed

- `Capsium::Reactor::Introspection.new` now takes the list of served
  packages (aggregation); `/introspect/status` `packagesLoaded`
  reflects the mount count.
- The reactor dispatch, endpoint and response handling are split into
  `Capsium::Reactor::Serving` (mount request serving),
  `Capsium::Reactor::Endpoints` (reactor-level endpoints) and
  `Capsium::Reactor::Responses` (HTTP response writers).
- WEBrick's `ProcHandler` (GET/POST/PUT only) is extended with
  `do_DELETE`/`do_PATCH` aliases so the writable-package REST verbs
  reach the mounted procs.
- `Metrics/ParameterLists` rubocop no longer counts keyword args (the
  reactor constructor takes one keyword per deploy-time concern).

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
- Reactor-level and per-package introspection endpoints (ARCHITECTURE.md
  section 7 follow-ons), extending `Capsium::Reactor::Introspection`:
  `GET /introspect/status` (`{status, uptime, packagesLoaded}`),
  `GET /introspect/config` (port, store dir, cacheControl, authEnabled,
  registry — deploy.json values and registry URL credentials are never
  exposed) and `GET /introspect/metrics`
  (`{uptime, requestsTotal, requestsByStatus}`) backed by the new
  thread-safe in-memory `Capsium::Reactor::Metrics` counter wired into
  the serving path, plus `GET /package/<name>/status`,
  `GET /package/<name>/metadata` and `GET /package/<name>/logs` (the
  reactor serves one package; any other name is a 404). `logs` returns
  the last N lines (`?lines=N`, default 100) from the new
  `Capsium::LogBuffer`, a small thread-safe ring buffer recording key
  serving events (reactor start, package reload, one line per served
  request). All endpoints are GET-only JSON (405 otherwise) and gated
  when `authentication.json` enables authentication.

### Changed

- `Metrics/ClassLength` rubocop budget raised to 150 for the reactor
  and introspection classes grown by the phase-3 endpoints.

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
