# frozen_string_literal: true

module Capsium
  class Package
    module Testing
      # What a test run needs: the extracted package directory and, when
      # route tests run, the base URL of the reactor serving the package.
      Context = Data.define(:package_path, :base_url)
    end
  end
end
