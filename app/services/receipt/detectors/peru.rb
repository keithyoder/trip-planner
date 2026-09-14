# frozen_string_literal: true

module Receipt
  module Detectors
    class Peru
      HOST_PATTERN = /sunat\.gob\.pe/

      def self.handles?(url)
        URI.parse(url).host.to_s.match?(HOST_PATTERN)
      rescue URI::InvalidURIError
        false
      end

      # TODO: SUNAT document types (boleta/factura/nota de crédito) aren't
      # yet distinguishable here — needs a real receipt to know where that
      # signal lives (likely encoded in the QR string itself, not the URL).
      def self.detect(_url)
        { document_type: :unknown, raw_key: nil }
      end
    end
  end
end
