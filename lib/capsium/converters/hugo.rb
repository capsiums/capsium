# frozen_string_literal: true

module Capsium
  module Converters
    # Hugo static export → Capsium. Walks the standard `public/`
    # output. Hugo emits per-section index.html files plus RSS feeds
    # (index.xml) and sitemap.xml; the latter are passed through as
    # plain assets (no special route handling).
    class Hugo < StaticSite
      # Hugo's auto-generated feeds (index.xml, sitemap.xml) — keep
      # them as routable assets rather than excluding them, since
      # downstream consumers (RSS readers) expect them.
      def asset_exclusions
        []
      end
    end
  end
end
