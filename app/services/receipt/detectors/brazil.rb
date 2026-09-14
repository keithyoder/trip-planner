# frozen_string_literal: true

module Receipt
  module Detectors
    class Brazil
      HOST_PATTERN = /sefaz\.\w{2}\.gov\.br/

      def self.handles?(url)
        URI.parse(url).host.to_s.match?(HOST_PATTERN)
      rescue URI::InvalidURIError
        false
      end

      def self.detect(url)
        key = Receipt::Brazil::DocumentKey.new(url)
        { document_type: key.valid? ? key.document_type : :unknown, raw_key: key.key }
      end
    end
  end
end
