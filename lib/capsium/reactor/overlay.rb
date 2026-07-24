# frozen_string_literal: true

require "fileutils"
require "json"

module Capsium
  class Reactor
    # The writable top overlay layer of a mounted package
    # (ARCHITECTURE.md section 5a): an append-only record of writes in
    # the reactor workdir. The immutable package on disk never changes;
    # content writes land under content/, deletions are tombstones in
    # .capsium-tombstones, and dataset mutations are a per-dataset JSON
    # operation log under data/. Everything is visible on the next
    # request (hot-swap) and reloads from disk when the reactor starts
    # over the same workdir.
    class Overlay
      # Base class for the typed overlay errors the APIs map to HTTP
      # statuses.
      class Error < Capsium::Error; end

      # The addressed item does not exist in the merged collection (404).
      class ItemNotFoundError < Error; end

      # The write conflicts with existing state, e.g. a duplicate item
      # id on append or a body id mismatch on replace (409).
      class ConflictError < Error; end

      # The dataset cannot take item writes (not a JSON collection) or
      # the addressed path is unsafe (422/400).
      class UnsupportedDatasetError < Error; end

      # The candidate document violates the dataset's JSON schema (422);
      # carries the schema error messages.
      class SchemaViolationError < Error
        attr_reader :messages

        def initialize(messages)
          @messages = messages
          super(messages.join("; "))
        end
      end

      TOMBSTONE_FILE = Package::MergedView::TOMBSTONE_FILE
      SAFE_NAME_PATTERN = /\A[\w.-]+\z/

      autoload :SqliteOps, "capsium/reactor/overlay/sqlite_ops"

      include SqliteOps

      attr_reader :root, :tombstones

      def initialize(root:)
        @root = root
        @tombstones = load_tombstones
        @logs = {}
      end

      def content_root = File.join(@root, "content")

      def data_root = File.join(@root, "data")

      # The overlay as the topmost MergedView layer. The tombstones set
      # is live: deletions are visible on the next resolve.
      def layer
        Package::MergedView::Layer.new(root: content_root,
                                       visibility: "private",
                                       tombstones: @tombstones)
      end

      # Writes a content file (create/overwrite), clearing any tombstone
      # for the path so it is served again.
      def write_content(content_relative, body)
        path = safe_content_path(content_relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
        @tombstones.delete(content_relative)
        persist_tombstones
      end

      # Tombstones a content path: it resolves 404 even when a lower
      # layer holds the file (ARCHITECTURE.md section 5a).
      def delete_content(content_relative)
        FileUtils.rm_f(safe_content_path(content_relative))
        @tombstones.add(content_relative)
        persist_tombstones
      end

      # The dataset as served: the base data untouched when no mutations
      # were recorded, the merged collection otherwise. SQLite datasets
      # served from the overlay DB once one exists (copy-on-write).
      def dataset_data(dataset)
        return sqlite_dataset_data(dataset) if dataset.config.sqlite?

        return dataset.data if mutation_log(dataset.name).empty?

        items(dataset)
      end

      # The merged item collection: base data plus the replayed
      # mutation log. SQLite datasets do not use the JSON op log — they
      # serve straight from the copy-on-write overlay DB.
      def items(dataset)
        return sqlite_collection(dataset) if dataset.config.sqlite?

        mutation_log(dataset.name).inject(base_items(dataset)) do |items, record|
          apply_op(items, record)
        end
      end

      def item(dataset, id)
        return sqlite_item(dataset, id) if dataset.config.sqlite?

        current = items(dataset)
        found = find_index(current, id)
        raise ItemNotFoundError, "no item #{id} in dataset #{dataset.name}" unless found

        current[found]
      end

      # Appends an item and returns its assigned id: the "id" field
      # convention, else the 1-based index as a string.
      def append_item(dataset, item)
        return sqlite_append_item(dataset, item) if dataset.config.sqlite?

        current = items(dataset)
        explicit = item_id(item)
        if explicit && find_index(current, explicit)
          raise ConflictError, "item id #{explicit} already exists in #{dataset.name}"
        end

        validate_candidate!(dataset, current + [item])
        record_op(dataset.name, "op" => "append", "item" => item)
        explicit || (current.size + 1).to_s
      end

      def replace_item(dataset, id, item)
        return sqlite_replace_item(dataset, id, item) if dataset.config.sqlite?

        current = items(dataset)
        index = find_index(current, id)
        raise ItemNotFoundError, "no item #{id} in dataset #{dataset.name}" unless index

        explicit = item_id(item)
        if explicit && explicit != id
          raise ConflictError, "body id #{explicit} does not match #{id}"
        end

        validate_candidate!(dataset, replaced(current, index, item))
        record_op(dataset.name, "op" => "replace", "id" => id, "item" => item)
      end

      def delete_item(dataset, id)
        return sqlite_delete_item(dataset, id) if dataset.config.sqlite?

        unless find_index(items(dataset), id)
          raise ItemNotFoundError, "no item #{id} in dataset #{dataset.name}"
        end

        record_op(dataset.name, "op" => "delete", "id" => id)
        nil
      end

      # Apply a parsed CollectionQuery (pagination + sort + filter) to
      # the dataset collection and return { items:, total:, etag: }.
      # For JSON datasets the work happens in Ruby; for SQLite the
      # query translates to SQL and runs against the overlay DB.
      #
      # Datasets whose stored value is not a JSON collection (a single
      # object, a map) bypass query semantics — those are read-only
      # documents, not addressable item collections, and the spec
      # promises their bytes back unchanged.
      def query_collection(dataset, query)
        return sqlite_query(dataset, query) if dataset.config.sqlite?

        data = dataset_data(dataset)
        unless data.is_a?(Array)
          return {
            items: data,
            total: nil,
            etag: DataApi::CollectionQuery.etag_for(data, 1)
          }
        end

        applied = query.apply_to_json(data)
        {
          items: applied[:items],
          total: applied[:total],
          etag: DataApi::CollectionQuery.etag_for(applied[:items], applied[:total])
        }
      end

      # The item id convention: an "id" field, else nil (positional).
      def item_id(item)
        item["id"].to_s if item.is_a?(Hash) && item.key?("id")
      end

      # Whether the dataset has recorded mutations.
      def mutations?(name) = !mutation_log(name).empty?

      private

      def base_items(dataset)
        base = dataset.data || []
        return deep_dup(base) if base.is_a?(Array)

        raise UnsupportedDatasetError,
              "dataset #{dataset.name} is not a JSON collection"
      end

      def validate_candidate!(dataset, candidate)
        errors = dataset.schema_errors_for(candidate)
        raise SchemaViolationError, errors unless errors.empty?
      end

      def apply_op(items, record)
        return items + [record["item"]] if record["op"] == "append"

        index = find_index(items, record["id"])
        return items unless index # base changed underneath: skip the op

        case record["op"]
        when "replace" then replaced(items, index, record["item"])
        when "delete" then items[0...index] + items[(index + 1)..]
        else raise Error, "unknown overlay op: #{record['op']}"
        end
      end

      def replaced(items, index, item)
        items[0...index] + [item] + items[(index + 1)..]
      end

      # Positional ids are the 1-based index as a string and only match
      # items without an explicit "id" field.
      def find_index(items, id)
        by_field = items.index { |item| item_id(item) == id }
        return by_field if by_field
        return nil unless id.to_s.match?(/\A[1-9]\d*\z/)

        index = id.to_i - 1
        index < items.size && item_id(items[index]).nil? ? index : nil
      end

      def mutation_log(name)
        @logs[name] ||= load_ops(name)
      end

      def record_op(name, record)
        mutation_log(name) << record
        FileUtils.mkdir_p(data_root)
        File.write(ops_path(name), JSON.generate(mutation_log(name)))
      end

      def load_ops(name)
        return [] unless name.match?(SAFE_NAME_PATTERN)

        path = ops_path(name)
        return [] unless File.file?(path)

        JSON.parse(File.read(path))
      end

      def ops_path(name)
        unless name.match?(SAFE_NAME_PATTERN)
          raise Error, "unsafe dataset name for the overlay: #{name}"
        end

        File.join(data_root, "#{name}.json")
      end

      def safe_content_path(content_relative)
        segments = content_relative.split("/")
        if segments.empty? || segments.any? { |segment| segment.empty? || segment == ".." }
          raise Error, "unsafe content path: #{content_relative}"
        end

        File.join(content_root, content_relative)
      end

      def deep_dup(data) = JSON.parse(JSON.generate(data))

      def load_tombstones
        path = File.join(content_root, TOMBSTONE_FILE)
        return Set.new unless File.file?(path)

        Set.new(JSON.parse(File.read(path)))
      end

      def persist_tombstones
        FileUtils.mkdir_p(content_root)
        File.write(File.join(content_root, TOMBSTONE_FILE),
                   JSON.generate(@tombstones.to_a))
      end
    end
  end
end
