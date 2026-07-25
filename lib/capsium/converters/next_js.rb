# frozen_string_literal: true

module Capsium
  module Converters
    # Next.js static export → Capsium. Walks the standard `out/`
    # directory produced by `next export` (or `output: export` in
    # next.config.js). Next emits both folder-style
    # (`/about/index.html`) and flat (`/about.html`) depending on
    # `trailingSlash` config; the base class's infer_routes_for
    # handles both, so no override is needed here.
    class NextJs < StaticSite
      def asset_exclusions
        # Next's .next/ build cache isn't emitted to out/ but the
        # exclude is here as defensive documentation if a future
        # Next version copies it.
        [".next"]
      end
    end
  end
end
