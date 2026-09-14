# frozen_string_literal: true

module Receipt
  module Brazil
    # Parses Brazil's national 44-digit chave de acesso, shared by every
    # electronic fiscal document model (NFe, NFCe, CTe, MDFe, NFCom...).
    class DocumentKey
      MODELS = {
        '55' => :nfe,
        '65' => :nfce,
        '57' => :cte,
        '58' => :mdfe,
        '62' => :nfcom
      }.freeze

      attr_reader :key

      def initialize(url)
        @key = extract_key(url)
      end

      def valid?
        key&.match?(/\A\d{44}\z/)
      end

      def model_code
        key[20, 2] if valid?
      end

      def document_type
        MODELS.fetch(model_code, :unknown)
      end

      private

      # The chave is the first pipe-delimited segment of the `p` query
      # param, whether pipes are literal or %7C-encoded — true for
      # NFCe/NFe/NFCom alike, since they share the same QR convention.
      def extract_key(url)
        uri = URI.parse(url)
        query = CGI.parse(uri.query.to_s)
        param = query['p']&.first
        param&.split('|')&.first
      end
    end
  end
end
