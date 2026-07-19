# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

module Capsium
  class Reactor
    # Folds a mounted package's base plus its overlay into a NEW
    # versioned .cap (name-version+patch.cap) in the reactor workdir:
    # overlay content files replace, tombstones delete, dataset mutation
    # logs replay into the dataset files (JSON/YAML per the source
    # extension). Manifest, routes and security.json are regenerated,
    # so the saved package passes `capsium package validate`.
    class PackageSaver
      def initialize(mount)
        @mount = mount
        @package = mount.package
        @overlay = mount.overlay
      end

      # Returns {path, sha256, name, version} of the saved .cap.
      def save(workdir)
        staging_parent = File.join(workdir, "saved")
        FileUtils.mkdir_p(staging_parent)
        stage = Dir.mktmpdir("fold-", staging_parent)
        begin
          fold_into(stage)
          output = Packager.new.pack(Package.new(stage), { force: true })
          { "path" => output,
            "sha256" => Digest::SHA256.file(output).hexdigest,
            "name" => @package.name,
            "version" => bumped_version }
        ensure
          FileUtils.remove_entry(stage)
        end
      end

      private

      def fold_into(stage)
        FileUtils.cp_r("#{@package.path}/.", stage)
        apply_content_overlay(stage)
        apply_dataset_overlays(stage)
        write_bumped_metadata(stage)
        # Regenerated at pack time from the folded tree.
        FileUtils.rm_f(File.join(stage, Package::MANIFEST_FILE))
        FileUtils.rm_f(File.join(stage, Package::ROUTES_FILE))
        FileUtils.rm_f(File.join(stage, Package::SECURITY_FILE))
      end

      def apply_content_overlay(stage)
        @overlay.tombstones.each do |relative|
          FileUtils.rm_f(File.join(stage, Package::CONTENT_DIR, relative))
        end
        Dir.glob(File.join(@overlay.content_root, "**", "*"), File::FNM_DOTMATCH).each do |file|
          next unless File.file?(file)

          relative = file.delete_prefix("#{@overlay.content_root}/")
          next if relative == Overlay::TOMBSTONE_FILE

          target = File.join(stage, Package::CONTENT_DIR, relative)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(file, target)
        end
      end

      def apply_dataset_overlays(stage)
        @package.storage.datasets.each do |dataset|
          next unless @overlay.mutations?(dataset.name)

          write_merged_dataset(stage, dataset, @overlay.items(dataset))
        end
      end

      def write_merged_dataset(stage, dataset, merged)
        target = File.join(stage, dataset.config.backing_file)
        case File.extname(target).downcase
        when ".yaml", ".yml" then File.write(target, YAML.dump(merged))
        else File.write(target, JSON.pretty_generate(merged))
        end
      end

      def bumped_version
        version = Package::Version.parse(@package.metadata.version)
        "#{version.major}.#{version.minor}.#{version.patch + 1}"
      end

      def write_bumped_metadata(stage)
        path = File.join(stage, Package::METADATA_FILE)
        metadata = JSON.parse(File.read(path))
        metadata["version"] = bumped_version
        File.write(path, JSON.pretty_generate(metadata))
      end
    end
  end
end
