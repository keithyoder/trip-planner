# frozen_string_literal: true

module Receipt
  module Adapters
    class Base
      # Every adapter implements #call(url) and returns a Normalized struct.
      # Detection (country + document type) already happened in
      # Receipt::Detector before an adapter is ever instantiated, so
      # adapters are pure parsers — no self.handles? needed here anymore.
      Normalized = Struct.new(
        :receipt_id, :receipt_url, :raw, :items, :vendor,
        :amount_cents, :currency, :occurred_at,
        keyword_init: true
      )

      def call(url)
        raise NotImplementedError
      end
    end
  end
end
