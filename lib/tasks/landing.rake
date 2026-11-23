# frozen_string_literal: true

namespace :landing do
  desc 'Rebuild the cached landing-page route map now (it also refreshes itself once a day)'
  task refresh_map: :environment do
    overview = Landing::Overview.build
    overview.refresh_map!
    puts "Landing map rebuilt for #{overview.trip.name} (#{overview.phase}, #{overview.today})"
  end
end
