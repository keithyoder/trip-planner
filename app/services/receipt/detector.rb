module Receipt
  class Detector
    Result = Struct.new(:country, :document_type, :raw_key, keyword_init: true)

    COUNTRY_DETECTORS = {
      brazil: 'Receipt::Detectors::Brazil',
      peru: 'Receipt::Detectors::Peru',
      argentina: 'Receipt::Detectors::Argentina',
      chile: 'Receipt::Detectors::Chile',
      bolivia: 'Receipt::Detectors::Bolivia'
    }.freeze

    def self.call(url)
      country_key, detector_class_name = COUNTRY_DETECTORS.find do |_, class_name|
        class_name.constantize.handles?(url)
      end

      return Result.new(country: :unknown, document_type: :unknown) unless detector_class_name

      detector_class = detector_class_name.constantize
      Result.new(country: country_key, **detector_class.detect(url))
    end
  end
end
