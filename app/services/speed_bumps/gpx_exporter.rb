module SpeedBumps
  class GpxExporter
    def self.export(events, name: 'Detected speed bumps')
      trackpoints = events.each_with_index.map do |event, i|
        <<~XML
          <trkpt lat="#{event[:lat]}" lon="#{event[:lon]}">
            <name>#{CGI.escapeHTML("Speed bump candidate #{i + 1}")}</name>
            <desc>#{CGI.escapeHTML("#{event[:from_speed]}→#{event[:to_speed]} km/h in #{event[:duration]}s, #{event[:from_time]}")}</desc>
            <time>#{event[:from_time].utc.iso8601}</time>
          </trkpt>
        XML
      end.join

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="trip-planner" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>#{CGI.escapeHTML(name)}</name>
          </metadata>
          <trk>
            <name>#{CGI.escapeHTML(name)}</name>
            <trkseg>
              #{trackpoints}
            </trkseg>
          </trk>
        </gpx>
      XML
    end
  end
end
