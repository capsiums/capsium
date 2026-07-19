# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium::LogBuffer do
  subject(:buffer) { described_class.new(capacity: 3) }

  it "keeps entries oldest-first and formats lines with a UTC timestamp" do
    buffer.add("first", timestamp: Time.utc(2026, 7, 19, 15, 0, 0))
    buffer.add("second", timestamp: Time.utc(2026, 7, 19, 15, 0, 1))

    expect(buffer.lines(10)).to eq(
      ["2026-07-19T15:00:00Z first", "2026-07-19T15:00:01Z second"]
    )
  end

  it "drops the oldest entry when over capacity" do
    %w[one two three four].each { |message| buffer.add(message) }

    expect(buffer.last(3).map(&:message)).to eq(%w[two three four])
    expect(buffer.lines(3).first).to end_with(" two")
  end

  it "returns the last n entries" do
    buffer.add("one")
    buffer.add("two")

    expect(buffer.last(1).map(&:message)).to eq(["two"])
    expect(buffer.last(0)).to eq([])
  end

  it "is thread-safe under concurrent adds" do
    buffer = described_class.new(capacity: 500)
    threads = Array.new(4) do |n|
      Thread.new { 250.times { |i| buffer.add("t#{n}-#{i}") } }
    end
    threads.each(&:join)

    expect(buffer.last(500).size).to eq(500)
    expect(buffer.last(1000).size).to eq(500)
  end

  it "rejects a capacity below 1" do
    expect { described_class.new(capacity: 0) }.to raise_error(ArgumentError)
  end
end
