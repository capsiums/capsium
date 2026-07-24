# frozen_string_literal: true

module Capsium
  class Reactor
    class Overlay
      # JSON-dataset mutation-history operations mixed into Overlay.
      # The Overlay stores the op log; this module exposes history,
      # point-in-time replay, and item-keyed diffs. SQLite datasets
      # use the COW DB directly and do not have an op log — methods
      # here answer empty / no-op for them.
      module HistoryOps
        # The mutation history of a JSON dataset, with monotonic 0-based
        # sequence numbers assigned in append order. Each entry carries
        # the op ("append"|"replace"|"delete"), the addressed id (where
        # applicable), the recorded item (for append/replace), and the
        # sequence number. SQLite datasets use the COW DB directly and
        # do not maintain an op log; their history endpoint answers an
        # empty array.
        def history(dataset)
          return [] if dataset.config.sqlite?

          mutation_log(dataset.name).each_with_index.map do |record, seq|
            { seq: seq }.merge(record)
          end
        end

        def history_at(dataset, seq)
          history(dataset).find { |record| record[:seq] == seq }
        end

        # Replays the mutation log up to and including `seq` against the
        # base collection. Useful for "what did the collection look like
        # at this point in time" views.
        def collection_at(dataset, seq)
          return items(dataset) if dataset.config.sqlite?

          records = mutation_log(dataset.name).take(seq + 1)
          records.inject(base_items(dataset)) do |acc, record|
            apply_op(acc, record)
          end
        end

        # Item-level diff between two points in time. Returns a hash
        # with :added, :removed, :changed — each an array of items
        # keyed by their stable id (explicit "id" field or positional
        # 1-based index). Custom format rather than RFC 6902 JSON Patch
        # because collection diffs make more sense keyed by id than by
        # array index (which shifts on every mutation).
        def diff(dataset, from_seq, to_seq)
          return empty_diff if dataset.config.sqlite?

          from = indexed_collection(collection_at(dataset, from_seq))
          to = indexed_collection(collection_at(dataset, to_seq))
          {
            added: (to.keys - from.keys).map { |id| to[id] },
            removed: (from.keys - to.keys).map { |id| from[id] },
            changed: changed_items(from, to)
          }
        end

        private

        def empty_diff
          { added: [], removed: [], changed: [] }
        end

        def changed_items(from, to)
          (to.keys & from.keys)
            .reject { |id| from[id] == to[id] }
            .map { |id| { id: id, from: from[id], to: to[id] } }
        end

        # Items keyed by their stable id (explicit "id" field, else the
        # 1-based positional as a string). Used by #diff to detect
        # add/remove/change between two collection snapshots.
        def indexed_collection(items)
          items.each_with_index.to_h do |item, index|
            id = item_id(item) || (index + 1).to_s
            [id, item]
          end
        end
      end
    end
  end
end
