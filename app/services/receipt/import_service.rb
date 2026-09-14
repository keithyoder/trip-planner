module Receipt
  class ImportService
    Result = Struct.new(:success?, :expense, :error, keyword_init: true)

    PARSERS = {
      %i[brazil nfce] => 'Receipt::Adapters::Brazil::Nfce',
      %i[brazil nfe] => 'Receipt::Adapters::Brazil::Nfe',
      %i[brazil nfcom] => 'Receipt::Adapters::Brazil::Nfcom',
      %i[peru unknown] => 'Receipt::Adapters::Peru::Sunat',
      %i[argentina unknown] => 'Receipt::Adapters::Argentina::Afip',
      %i[chile unknown] => 'Receipt::Adapters::Chile::Sii',
      %i[bolivia unknown] => 'Receipt::Adapters::Bolivia::Sin'
    }.freeze

    def initialize(stop:, url:, category:)
      @stop     = stop
      @url      = url
      @category = category
    end

    def call
      detection = Detector.call(@url)
      parser_class_name = PARSERS[[detection.country, detection.document_type]]

      unless parser_class_name
        return Result.new(
          success?: false,
          error: "Unsupported receipt: #{detection.country}/#{detection.document_type}"
        )
      end

      parser_class = parser_class_name.constantize
      data = parser_class.new.call(@url)
      expense = build_expense(data)

      if expense.save
        Result.new(success?: true, expense: expense)
      else
        Result.new(success?: false, error: expense.errors.full_messages.to_sentence)
      end
    rescue StandardError => e
      Result.new(success?: false, error: e.message)
    end

    private

    def build_expense(data)
      @stop.expenses.build(
        category: @category,
        receipt_id: data.receipt_id,
        receipt_url: data.receipt_url,
        raw_receipt_xml: data.raw,
        items: data.items,
        vendor: data.vendor,
        amount_cents: data.amount_cents,
        amount_currency: data.currency
      )
    end
  end
end
