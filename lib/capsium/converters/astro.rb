# frozen_string_literal: true

module Capsium
  module Converters
    # Astro static export → Capsium. Walks the standard `dist/`
    # output, copying assets under `content/`. Astro bundles hashed
    # CSS/JS under `_astro/`; those are preserved as a single routed
    # directory (not URL-rewritten) so the runtime URL matches what
    # the built HTML expects.
    class Astro < StaticSite
      ASSET_BUNDLE_DIR = "_astro"

      def asset_exclusions
        # Astro emits a .astro/ directory for data collections and a
        # _astro/ bundle dir; both are kept (they're real assets) but
        # only _astro is universally present. Other exclusions live
        # in the constructor's exclude: list.
        []
      end
    end
  end
end
