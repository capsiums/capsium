# frozen_string_literal: true

require "json"
require "stringio"
require "zip"

# Builders for composite-package specs (ARCHITECTURE.md section 4a):
# source package directories packed into a store of .cap files.
module CompositeSpecHelper
  BASE_GUID = "https://example.com/capsiums/base-package"
  OTHER_GUID = "https://example.com/capsiums/other-package"
  CIRCULAR_A_GUID = "https://example.com/capsiums/circular-a"
  CIRCULAR_B_GUID = "https://example.com/capsiums/circular-b"

  MIME_BY_EXTENSION = {
    ".css" => "text/css", ".html" => "text/html",
    ".js" => "text/javascript", ".txt" => "text/plain"
  }.freeze

  module_function

  # A store with base-package 1.0.0/1.2.0/2.0.0 and other-package 0.9.0.
  # With index: true, index.json pins the base GUID to the 1.0.0 file.
  def build_store(dir, index: false)
    store = File.join(dir, "store")
    FileUtils.mkdir_p(store)
    %w[1.0.0 1.2.0 2.0.0].each do |version|
      pack(store, base_package(store, version))
    end
    pack(store, write_package(store, name: "other-package", version: "0.9.0",
                                     guid: OTHER_GUID,
                                     files: { "other.txt" => "other 0.9.0" }))
    if index
      File.write(File.join(store, "index.json"),
                 JSON.generate({ BASE_GUID => "base-package-1.0.0.cap" }))
    end
    store
  end

  # A store containing a single dependency-free package.
  def build_single_package_store(dir, name:, version:, guid:,
                                 files: { "index.html" => "<html></html>" })
    store = File.join(dir, "store")
    FileUtils.mkdir_p(store)
    pack(store, write_package(store, name: name, version: version,
                                     guid: guid, files: files))
    store
  end

  # A store of two packages depending on each other.
  def build_circular_store(dir)
    store = File.join(dir, "store")
    FileUtils.mkdir_p(store)
    zip_package(write_package(store, name: "circular-a", version: "1.0.0",
                                     guid: CIRCULAR_A_GUID,
                                     dependencies: { CIRCULAR_B_GUID => "*" },
                                     files: { "a.txt" => "a" }),
                File.join(store, "circular-a-1.0.0.cap"))
    zip_package(write_package(store, name: "circular-b", version: "1.0.0",
                                     guid: CIRCULAR_B_GUID,
                                     dependencies: { CIRCULAR_A_GUID => "*" },
                                     files: { "b.txt" => "b" }),
                File.join(store, "circular-b-1.0.0.cap"))
    store
  end

  def base_package(dir, version)
    write_package(
      dir, name: "base-package", version: version, guid: BASE_GUID,
           files: {
             "app.js" => "console.log('base #{version}');",
             "public.txt" => "public #{version}",
             "secret.txt" => "secret #{version}",
             "shared.txt" => "base #{version} shared"
           },
           private_resources: ["secret.txt"]
    )
  end

  # A dependent package directory (unpacked) declaring the given
  # dependencies and routes.
  def write_dependent(dir, name:, dependencies:, routes:)
    package_dir = File.join(dir, name)
    FileUtils.mkdir_p(File.join(package_dir, "content"))
    write_metadata(package_dir, name: name, version: "0.1.0",
                                guid: "https://example.com/capsiums/#{name}",
                                dependencies: dependencies)
    File.write(File.join(package_dir, "content", "index.html"),
               "<html><body>#{name}</body></html>")
    File.write(File.join(package_dir, "routes.json"),
               JSON.pretty_generate({ "routes" => routes }))
    package_dir
  end

  def write_package(dir, name:, version:, guid:, dependencies: {}, files: {},
                    private_resources: [])
    package_dir = File.join(dir, "#{name}-#{version}")
    FileUtils.mkdir_p(File.join(package_dir, "content"))
    write_metadata(package_dir, name: name, version: version, guid: guid,
                                dependencies: dependencies)
    files.each do |path, body|
      File.write(File.join(package_dir, "content", path), body)
    end
    write_manifest(package_dir, files.keys, private_resources)
    package_dir
  end

  def write_metadata(package_dir, name:, version:, guid:, dependencies: {})
    metadata = {
      "name" => name,
      "version" => version,
      "description" => "#{name} #{version}",
      "guid" => guid,
      "uuid" => "11111111-2222-3333-4444-555555555555",
      "dependencies" => dependencies
    }
    File.write(File.join(package_dir, "metadata.json"),
               JSON.pretty_generate(metadata))
  end

  def write_manifest(package_dir, paths, private_resources)
    resources = paths.sort.to_h do |path|
      visibility = private_resources.include?(path) ? "private" : "exported"
      ["content/#{path}",
       { "type" => MIME_BY_EXTENSION.fetch(File.extname(path)),
         "visibility" => visibility }]
    end
    File.write(File.join(package_dir, "manifest.json"),
               JSON.pretty_generate({ "resources" => resources }))
  end

  # Packs a dependency-free source directory through the Packager
  # (generating security.json) and removes the source, leaving the .cap
  # in the store directory.
  def pack(store_dir, package_dir)
    quietly do
      Capsium::Packager.new.pack(Capsium::Package.new(package_dir), { force: true })
    end
    FileUtils.rm_rf(package_dir)
    File.join(store_dir, "#{File.basename(package_dir)}.cap")
  end

  # Zips a source directory directly, without loading it as a Package —
  # for packages whose dependencies cannot resolve at pack time (e.g.
  # circular fixtures).
  def zip_package(package_dir, cap_path)
    Zip::File.open(cap_path, create: true) do |zip|
      Dir[File.join(package_dir, "**", "**")].each do |file|
        zip.add(file.sub("#{package_dir}/", ""), file)
      end
    end
    FileUtils.rm_rf(package_dir)
    cap_path
  end

  def quietly
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
