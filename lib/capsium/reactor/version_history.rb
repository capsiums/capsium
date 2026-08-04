# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Capsium
  class Reactor
    # Version history for one mounted package: every save records the
    # resulting .cap on disk plus a metadata entry under the reactor's
    # workdir (versions/<package-name>.jsonl, one JSON record per line).
    # The history is the substrate for GET /package/<name>/versions
    # and POST /package/<name>/rollback.
    #
    # Storage choice: JSONL (append-only, line-delimited). Each line is
    # one record, no array to rewrite. Recovery on partial write is
    # line-by-line. Sorting + filtering happen at read time.
    class VersionHistory
      RECORD_KEYS = %i[saved_at version sha256 path note].freeze

      Record = Data.define(*RECORD_KEYS) do
        def to_h
          super.transform_keys(&:to_s)
        end
      end

      # `dir` is the workdir; `package_name` is the mount's package name
      # (one history file per package).
      def initialize(dir:, package_name:)
        @package_name = package_name
        @path = File.join(dir, "versions", "#{package_name}.jsonl")
      end

      # Records one save. Idempotent on sha256: re-saving the same bytes
      # doesn't double-record. Returns the persisted Record.
      def record(version:, sha256:, path:, note: nil)
        FileUtils.mkdir_p(File.dirname(@path))
        existing = find_by_sha256(sha256)
        return existing if existing

        record = Record.new(
          saved_at: Time.now.utc.iso8601,
          version: version,
          sha256: sha256,
          path: path,
          note: note
        )
        File.open(@path, "a") { |f| f.puts(JSON.generate(record.to_h)) }
        record
      end

      # Every recorded version, oldest first.
      def all
        return [] unless File.file?(@path)

        File.readlines(@path, chomp: true).filter_map do |line|
          next if line.strip.empty?

          hash = JSON.parse(line)
          Record.new(
            saved_at: hash.fetch("saved_at"),
            version: hash.fetch("version"),
            sha256: hash.fetch("sha256"),
            path: hash.fetch("path"),
            note: hash["note"]
          )
        end
      end

      # Find a record by version string OR sha256. Newest match wins.
      def find(version_or_sha)
        matches = all.select do |record|
          record.version == version_or_sha || record.sha256 == version_or_sha
        end
        matches.last
      end

      private

      def find_by_sha256(sha256)
        all.reverse.find { |record| record.sha256 == sha256 }
      end
    end
  end
end
