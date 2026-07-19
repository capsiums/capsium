# frozen_string_literal: true

require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "tempfile"
require "timeout"
require "uri"

module Capsium
  class Registry
    # A read-only static registry behind an https base URL (any static
    # host: GitHub Pages, S3, nginx). index.json and .cap files are
    # fetched over net/http with redirect following and timeouts; plain
    # http is accepted for loopback hosts only (local development).
    class Remote < Registry
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      MAX_REDIRECTS = 5
      LOOPBACK_NETWORKS = [IPAddr.new("127.0.0.0/8"), IPAddr.new("::1/128")].freeze

      attr_reader :base_url

      def initialize(base_url)
        super()
        @base_url = base_url.to_s.sub(%r{/+\z}, "")
        validate_scheme!(request_uri(INDEX_FILE))
      end

      def location = base_url

      private

      def index
        @index ||= parse_index(fetch_bytes(INDEX_FILE))
      rescue FetchError => e
        raise InvalidRegistryError, "no readable #{INDEX_FILE} at #{base_url}: #{e.message}"
      end

      def with_entry_file(entry)
        Tempfile.create(["capsium-registry", ".cap"]) do |tmp|
          tmp.binmode
          tmp.write(fetch_bytes(entry.file))
          tmp.flush
          yield tmp.path
        end
      end

      def fetch_bytes(relative_path)
        uri = request_uri(relative_path)
        MAX_REDIRECTS.times do
          response = http_get(uri)
          return response.body if response.is_a?(Net::HTTPSuccess)

          uri = follow_redirect(uri, response)
        end
        raise FetchError, "GET #{uri}: too many redirects (limit #{MAX_REDIRECTS})"
      end

      def follow_redirect(uri, response)
        location = response["location"] if response.is_a?(Net::HTTPRedirection)
        raise FetchError, "GET #{uri} failed: HTTP #{response.code}" if location.nil?

        target = URI.join(uri.to_s, location)
        validate_scheme!(target)
        target
      end

      def http_get(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.is_a?(URI::HTTPS)
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.request(Net::HTTP::Get.new(uri.request_uri))
      rescue Timeout::Error, SocketError, SystemCallError,
             OpenSSL::SSL::SSLError => e
        raise FetchError, "GET #{uri} failed: #{e.message}"
      end

      def request_uri(relative_path)
        URI.parse("#{base_url}/#{relative_path}")
      rescue URI::InvalidURIError => e
        raise InvalidRegistryError, "invalid registry URL #{base_url.inspect}: #{e.message}"
      end

      def validate_scheme!(uri)
        return if uri.is_a?(URI::HTTPS)
        return if uri.is_a?(URI::HTTP) && loopback_host?(uri.host)

        raise InvalidRegistryError,
              "registry URL must use https (plain http for loopback only): #{uri}"
      end

      def loopback_host?(host)
        return true if host == "localhost" || host.to_s.end_with?(".localhost")

        address = IPAddr.new(host)
        LOOPBACK_NETWORKS.any? { |network| network.include?(address) }
      rescue IPAddr::InvalidAddressError
        false
      end
    end
  end
end
