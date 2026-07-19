# frozen_string_literal: true

module Capsium
  class Package
    # A semantic version (MAJOR.MINOR.PATCH[-prerelease][+build]) with
    # semver precedence ordering. Build metadata is parsed but ignored
    # for precedence, per semver.org item 10.
    class Version
      include Comparable

      PATTERN = /\A(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?\z/

      attr_reader :major, :minor, :patch, :prerelease

      def self.parse(string)
        match = PATTERN.match(string.to_s.strip)
        raise Error, "Invalid semver version: #{string.inspect}" unless match

        new(match[1].to_i, match[2].to_i, match[3].to_i, match[4])
      end

      def initialize(major, minor, patch, prerelease = nil)
        @major = major
        @minor = minor
        @patch = patch
        @prerelease = prerelease
      end

      def <=>(other)
        core = [major, minor, patch] <=> [other.major, other.minor, other.patch]
        return core unless core.zero?

        compare_prerelease(other)
      end

      def to_s
        "#{major}.#{minor}.#{patch}#{"-#{prerelease}" if prerelease}"
      end

      private

      # semver.org item 11: a release outranks its prereleases; numeric
      # identifiers compare numerically and rank below alphanumeric ones;
      # a longer identifier list outranks a shorter prefix.
      def compare_prerelease(other)
        own_rank = prerelease.nil? ? 1 : 0
        their_rank = other.prerelease.nil? ? 1 : 0
        return own_rank <=> their_rank unless own_rank == their_rank
        return 0 if prerelease.nil?

        compare_identifier_lists(prerelease.split("."),
                                 other.prerelease.split("."))
      end

      def compare_identifier_lists(own_list, their_list)
        [own_list.length, their_list.length].max.times do |index|
          own = own_list[index]
          theirs = their_list[index]
          return 1 if theirs.nil?
          return -1 if own.nil?

          comparison = compare_identifier(own, theirs)
          return comparison unless comparison.zero?
        end
        0
      end

      def compare_identifier(own, theirs)
        own_numeric = own.match?(/\A\d+\z/)
        theirs_numeric = theirs.match?(/\A\d+\z/)
        return own.to_i <=> theirs.to_i if own_numeric && theirs_numeric
        return -1 if own_numeric
        return 1 if theirs_numeric

        own <=> theirs
      end
    end

    # A semver range for metadata.dependencies (ARCHITECTURE.md section
    # 4a), covering the standard's examples: "*", exact versions,
    # wildcards and partials ("1.x", "1.2.x", "1.2"), caret ("^1.2.3"),
    # tilde ("~1.2.3"), comparison operators (>=, <=, >, <, =) and
    # conjunctions joined by comma and/or space (">=1.0.0, <2.0.0").
    class VersionRange
      NUMERIC_PART = /\A(\d+)(?:\.(\d+)|\.(?:x|X|\*))?(?:\.(?:\d+|x|X|\*))?(?:-[^\s,]+)?\z/
      WILDCARD_PART = /\A(?:x|X|\*)\z/

      def self.parse(string)
        terms = string.to_s.strip.split(/[,\s]+/).reject(&:empty?)
        return new([[">=", Version.new(0, 0, 0)]]) if terms.empty? || terms == ["*"]

        new(terms.flat_map { |term| expand_term(term) })
      end

      # Expands one range term to a list of [operator, Version] bounds.
      def self.expand_term(term)
        case term
        when /\A\^(.+)\z/ then caret_bounds_for(Regexp.last_match(1))
        when /\A~(.+)\z/ then tilde_bounds_for(Regexp.last_match(1))
        when /\A(>=|<=|>|<|==?)(.+)\z/
          [[normalize_operator(Regexp.last_match(1)), Version.parse(pad(Regexp.last_match(2)))]]
        else
          expand_bare(term)
        end
      end
      private_class_method :expand_term

      # Bare terms: exact versions, partials ("1", "1.2") and wildcards
      # ("1.x", "1.2.x"). A partial behaves like the same-position
      # wildcard: "1" is "1.x", "1.2" is "1.2.x".
      def self.expand_bare(term)
        raise Error, "Invalid semver range term: #{term.inspect}" unless NUMERIC_PART.match?(term)

        parts = term.split("-", 2).first.split(".")
        return caret_bounds(Version.new(parts[0].to_i, 0, 0)) if wildcard_at?(parts, 1)
        return tilde_bounds(Version.new(parts[0].to_i, parts[1].to_i, 0)) if wildcard_at?(parts, 2)

        [["=", Version.parse(term)]]
      end
      private_class_method :expand_bare

      def self.wildcard_at?(parts, index)
        parts.length <= index || WILDCARD_PART.match?(parts[index])
      end
      private_class_method :wildcard_at?

      # Pads partial versions ("1.2") with zeros so operators accept them.
      def self.pad(partial)
        parts = partial.split("-", 2)
        core = parts.first.split(".")
        core << "0" while core.length < 3
        [core.join("."), parts[1]].compact.join("-")
      end
      private_class_method :pad

      # Caret bounds keeping the given precision: "^1" is < 2.0.0 and
      # "^0.0" is < 0.1.0 (npm semantics); full versions use caret rules.
      def self.caret_bounds_for(partial)
        parts = partial.split("-", 2).first.split(".")
        version = Version.parse(pad(partial))
        return [[">=", version], ["<", Version.new(version.major + 1, 0, 0)]] if parts.length < 2
        if parts.length < 3 && version.major.zero?
          return [[">=", version], ["<", Version.new(0, version.minor + 1, 0)]]
        end

        caret_bounds(version)
      end
      private_class_method :caret_bounds_for

      # Tilde bounds keeping the given precision: "~1" is < 2.0.0.
      def self.tilde_bounds_for(partial)
        parts = partial.split("-", 2).first.split(".")
        version = Version.parse(pad(partial))
        return [[">=", version], ["<", Version.new(version.major + 1, 0, 0)]] if parts.length < 2

        tilde_bounds(version)
      end
      private_class_method :tilde_bounds_for

      def self.caret_bounds(version)
        upper = if version.major.positive?
                  Version.new(version.major + 1, 0, 0)
                elsif version.minor.positive?
                  Version.new(0, version.minor + 1, 0)
                else
                  Version.new(0, 0, version.patch + 1)
                end
        [[">=", version], ["<", upper]]
      end
      private_class_method :caret_bounds

      def self.tilde_bounds(version)
        [[">=", version], ["<", Version.new(version.major, version.minor + 1, 0)]]
      end
      private_class_method :tilde_bounds

      def self.normalize_operator(operator)
        operator == "==" ? "=" : operator
      end
      private_class_method :normalize_operator

      def initialize(bounds)
        @bounds = bounds
      end

      def satisfied_by?(version)
        version = Version.parse(version) unless version.is_a?(Version)
        @bounds.all? { |operator, bound| holds?(operator, version <=> bound) }
      end

      private

      def holds?(operator, comparison)
        case operator
        when ">=" then comparison >= 0
        when "<=" then comparison <= 0
        when ">" then comparison.positive?
        when "<" then comparison.negative?
        else comparison.zero?
        end
      end
    end
  end
end
