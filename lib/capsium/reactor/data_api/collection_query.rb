# frozen_string_literal: true

require "digest"
require "json"

module Capsium
  class Reactor
    class DataApi
      # Parsed query-string parameters for a dataset collection GET.
      # Encapsulates pagination, sort, and equality-filter semantics so
      # the DataApi and the Overlay can apply them uniformly to both
      # JSON and SQLite backends without re-parsing the request.
      #
      # Query parameters (all optional):
      #   limit=<N>       - cap on items returned (default: 100, max: 1000)
      #   offset=<N>      - 0-based offset into the result set
      #   sort=<field>    - sort ascending by field
      #   sort=-<field>   - sort descending by field
      #                     (comma-separated for multi-field sort)
      #   <field>=<value> - exact-match filter on a top-level field
      #                     (multiple params AND together; reserved
      #                     params limit/offset/sort are not treated as
      #                     filters)
      class CollectionQuery
        DEFAULT_LIMIT = 100
        MAX_LIMIT = 1000
        # Reserved query params (not treated as filters): pagination/
        # sort controls plus the action-history endpoints (at, from, to).
        RESERVED = %w[limit offset sort at from to].freeze

        attr_reader :limit, :offset, :sorts, :filters

        def initialize(limit: DEFAULT_LIMIT, offset: 0, sorts: [], filters: {})
          @limit = clamp_limit(limit)
          @offset = clamp_offset(offset)
          @sorts = sorts
          @filters = filters
        end

        # Parses a WEBrick query hash (or any string-keyed hash) into a
        # CollectionQuery. Tolerates nil and empty.
        def self.from_query(query)
          return new if query.nil? || query.empty?

          new(
            limit: parse_int(query["limit"], DEFAULT_LIMIT),
            offset: parse_int(query["offset"], 0),
            sorts: parse_sorts(query["sort"]),
            filters: extract_filters(query)
          )
        end

        # Apply pagination/sort/filter to a JSON collection (array of
        # hashes). Returns a hash with :items, :total (post-filter,
        # pre-pagination count), suitable for ETag computation.
        def apply_to_json(items)
          filtered = filters.empty? ? items : filter_json(items)
          sorted = sorts.empty? ? filtered : sort_json(filtered)
          {
            items: sorted.slice(offset, limit) || [],
            total: sorted.size
          }
        end

        # Builds SQL fragments for a SQLite SELECT. Returns a hash with
        # :where (array of clauses), :params (array of bind values),
        # :order (ORDER BY clause or nil), :limit, :offset.
        def to_sql
          {
            where: filters.map { |field, _value| "#{field} = ?" },
            params: filters.values,
            order: sorts.empty? ? nil : build_sql_order,
            limit: limit,
            offset: offset
          }
        end

        # Stable ETag for the result set: derived from the post-filter,
        # pre-pagination items so two requests that match the same
        # underlying state produce the same tag.
        def self.etag_for(items, total)
          payload = { n: total, sha: Digest::SHA256.hexdigest(JSON.generate(items)) }
          digest = Digest::SHA256.hexdigest(JSON.generate(payload))
          "\"#{digest[0, 16]}\""
        end

        class << self
          private

          def parse_int(value, default)
            return default if value.to_s.empty?

            Integer(value)
          rescue ArgumentError
            default
          end

          def parse_sorts(value)
            return [] if value.to_s.empty?

            value.split(",").map do |field|
              field = field.to_s
              if field.start_with?("-")
                { field: field[1..], direction: :desc }
              else
                { field: field, direction: :asc }
              end
            end
          end

          def extract_filters(query)
            query.except(*RESERVED)
                 .to_h { |key, value| [key.to_s, value.to_s] }
          end
        end

        private

        def clamp_limit(value)
          return DEFAULT_LIMIT if value.nil? || value <= 0

          [value, MAX_LIMIT].min
        end

        def clamp_offset(value)
          return 0 if value.nil? || value.negative?

          value
        end

        def filter_json(items)
          items.select do |item|
            next false unless item.is_a?(Hash)

            filters.all? do |field, value|
              item[field].to_s == value
            end
          end
        end

        def sort_json(items)
          items.sort_by do |item|
            sorts.map do |sort_spec|
              value = item.is_a?(Hash) ? item[sort_spec[:field]] : nil
              SortKey.new(value, sort_spec[:direction])
            end
          end
        end

        def build_sql_order
          sorts.map do |sort_spec|
            "#{sort_spec[:field]} #{sort_spec[:direction] == :desc ? 'DESC' : 'ASC'}"
          end.join(", ")
        end

        # Comparable wrapper that handles direction by reversing the
        # spaceship for :desc. nil sorts first ascending (matching
        # SQL's default NULLS FIRST on Postgres / SQLite).
        SortKey = Struct.new(:value, :direction) do
          include Comparable

          def <=>(other)
            cmp = compare(value, other.value)
            direction == :desc ? -cmp : cmp
          end

          private

          def compare(left, right)
            return 0 if left.nil? && right.nil?
            return -1 if left.nil?
            return 1 if right.nil?
            return left <=> right if comparable?(left, right)

            left.to_s <=> right.to_s
          end

          def comparable?(left, right)
            (left.is_a?(Numeric) && right.is_a?(Numeric)) ||
              (left.is_a?(String) && right.is_a?(String))
          end
        end
        private_constant :SortKey
      end
    end
  end
end
