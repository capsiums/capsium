# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "webrick"

RSpec.describe Capsium::Reactor::DataApi::CollectionQuery do
  describe ".from_query" do
    it "returns defaults for nil/empty" do
      expect(described_class.from_query(nil).limit).to eq(100)
      expect(described_class.from_query({}).limit).to eq(100)
    end

    it "parses limit and offset" do
      q = described_class.from_query("limit" => "10", "offset" => "20")
      expect(q.limit).to eq(10)
      expect(q.offset).to eq(20)
    end

    it "clamps limit to MAX_LIMIT" do
      q = described_class.from_query("limit" => "100000")
      expect(q.limit).to eq(1000)
    end

    it "falls back to default for invalid integers" do
      q = described_class.from_query("limit" => "abc")
      expect(q.limit).to eq(100)
    end

    it "parses single and multi sort with - prefix for descending" do
      q = described_class.from_query("sort" => "title")
      expect(q.sorts).to eq([{ field: "title", direction: :asc }])

      q = described_class.from_query("sort" => "-created_at")
      expect(q.sorts).to eq([{ field: "created_at", direction: :desc }])

      q = described_class.from_query("sort" => "-priority,title")
      expect(q.sorts).to eq([
                              { field: "priority", direction: :desc },
                              { field: "title", direction: :asc }
                            ])
    end

    it "extracts top-level equality filters (excluding reserved params)" do
      q = described_class.from_query("title" => "Foo", "limit" => "5",
                                     "category" => "bar")
      expect(q.filters).to eq({ "title" => "Foo", "category" => "bar" })
    end
  end

  describe "#apply_to_json" do
    let(:items) do
      [
        { "id" => "1", "title" => "Banana", "priority" => 1 },
        { "id" => "2", "title" => "Apple", "priority" => 3 },
        { "id" => "3", "title" => "Cherry", "priority" => 2 },
        { "id" => "4", "title" => "Apple", "priority" => 1 }
      ]
    end

    it "paginates with limit and offset" do
      q = described_class.from_query("limit" => "2", "offset" => "1")
      result = q.apply_to_json(items)
      expect(result[:items].map { |i| i["id"] }).to eq(%w[2 3])
      expect(result[:total]).to eq(4)
    end

    it "filters by exact match" do
      q = described_class.from_query("title" => "Apple")
      result = q.apply_to_json(items)
      expect(result[:items].map { |i| i["id"] }).to eq(%w[2 4])
      expect(result[:total]).to eq(2)
    end

    it "ANDs multiple filters" do
      q = described_class.from_query("title" => "Apple", "priority" => "1")
      result = q.apply_to_json(items)
      expect(result[:items].map { |i| i["id"] }).to eq(%w[4])
    end

    it "sorts ascending and descending" do
      asc = described_class.from_query("sort" => "title")
      expect(asc.apply_to_json(items)[:items].map { |i| i["title"] })
        .to eq(%w[Apple Apple Banana Cherry])

      desc = described_class.from_query("sort" => "-title")
      expect(desc.apply_to_json(items)[:items].map { |i| i["title"] })
        .to eq(%w[Cherry Banana Apple Apple])
    end

    it "sorts by multiple fields" do
      q = described_class.from_query("sort" => "title,-priority")
      result = q.apply_to_json(items)
      expect(result[:items].map { |i| [i["title"], i["priority"]] })
        .to eq([["Apple", 3], ["Apple", 1], ["Banana", 1], ["Cherry", 2]])
    end

    it "combines filter, sort, and pagination" do
      q = described_class.from_query("title" => "Apple", "sort" => "-priority",
                                     "limit" => "1")
      result = q.apply_to_json(items)
      expect(result[:items].map { |i| i["id"] }).to eq(%w[2])
      expect(result[:total]).to eq(2)
    end

    it "handles numeric vs string sort comparison without crashing" do
      mixed = [
        { "id" => "1", "v" => 10 },
        { "id" => "2", "v" => "abc" },
        { "id" => "3", "v" => 5 }
      ]
      q = described_class.from_query("sort" => "v")
      result = q.apply_to_json(mixed)
      expect(result[:items].size).to eq(3)
    end

    it "places nil first ascending, last descending" do
      with_nils = [
        { "id" => "1", "v" => "b" },
        { "id" => "2", "v" => nil },
        { "id" => "3", "v" => "a" }
      ]
      asc = described_class.from_query("sort" => "v")
      expect(asc.apply_to_json(with_nils)[:items].map { |i| i["id"] })
        .to eq(%w[2 3 1])
      desc = described_class.from_query("sort" => "-v")
      expect(desc.apply_to_json(with_nils)[:items].map { |i| i["id"] })
        .to eq(%w[1 3 2])
    end
  end

  describe ".etag_for" do
    it "produces a quoted short hex tag" do
      etag = described_class.etag_for([{ "a" => 1 }], 1)
      expect(etag).to match(/\A"[0-9a-f]{16}"\z/)
    end

    it "is stable for identical input" do
      e1 = described_class.etag_for([{ "a" => 1 }], 1)
      e2 = described_class.etag_for([{ "a" => 1 }], 1)
      expect(e1).to eq(e2)
    end

    it "changes when the items change" do
      e1 = described_class.etag_for([{ "a" => 1 }], 1)
      e2 = described_class.etag_for([{ "a" => 2 }], 1)
      expect(e1).not_to eq(e2)
    end

    it "changes when total changes even with identical items" do
      e1 = described_class.etag_for([{ "a" => 1 }], 1)
      e2 = described_class.etag_for([{ "a" => 1 }], 5)
      expect(e1).not_to eq(e2)
    end
  end

  describe "#to_sql" do
    it "builds WHERE clauses from filters" do
      q = described_class.from_query("title" => "Foo", "category" => "bar")
      sql = q.to_sql
      expect(sql[:where]).to include("title = ?")
      expect(sql[:where]).to include("category = ?")
      expect(sql[:params]).to include("Foo")
      expect(sql[:params]).to include("bar")
    end

    it "builds ORDER BY from sorts" do
      q = described_class.from_query("sort" => "-priority,title")
      sql = q.to_sql
      expect(sql[:order]).to eq("priority DESC, title ASC")
    end

    it "returns nil order when no sorts" do
      q = described_class.from_query({})
      expect(q.to_sql[:order]).to be_nil
    end

    it "preserves limit and offset" do
      q = described_class.from_query("limit" => "50", "offset" => "100")
      expect(q.to_sql[:limit]).to eq(50)
      expect(q.to_sql[:offset]).to eq(100)
    end
  end
end
