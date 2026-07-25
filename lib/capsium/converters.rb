# frozen_string_literal: true

module Capsium
  module Converters
    autoload :Astro, "capsium/converters/astro"
    autoload :Hugo, "capsium/converters/hugo"
    autoload :Jekyll, "capsium/converters/jekyll"
    autoload :NextJs, "capsium/converters/next_js"
    autoload :StaticSite, "capsium/converters/static_site"
  end
end
