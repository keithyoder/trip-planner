# frozen_string_literal: true

# Presentation of the landing page's trip counter, km figures, map caption and
# social links. The numbers themselves come from Landing::Overview.
module LandingHelper
  SOCIAL_CHANNELS = %i[substack instagram youtube facebook].freeze
  SOCIAL_NAMES = { substack: 'Substack', instagram: 'Instagram', youtube: 'YouTube', facebook: 'Facebook' }.freeze

  # Static brand icons from the design (paper on the raised surface).
  SOCIAL_ICONS = {
    substack: '<svg class="social-ico" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' \
              '<path d="M4 3h16v2.6H4zM4 7.7h16v2.6H4zM4 12.4h16V22l-8-4.4L4 22z"/></svg>',
    instagram: '<svg class="social-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' \
               'stroke-width="2.2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="5"/>' \
               '<circle cx="12" cy="12" r="4.2"/>' \
               '<circle cx="17.4" cy="6.6" r="1.2" fill="currentColor" stroke="none"/></svg>',
    youtube: '<svg class="social-ico" viewBox="0 0 24 24" aria-hidden="true">' \
             '<rect x="1.5" y="4.5" width="21" height="15" rx="4.5" fill="currentColor"/>' \
             '<path d="M10 8.6v6.8l5.8-3.4z" fill="#22211f"/></svg>',
    facebook: '<svg class="social-ico" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' \
              '<path d="M13.6 22v-8.2h2.8l.5-3.3h-3.3V8.4c0-.9.4-1.8 1.9-1.8h1.5V3.8s-1.4-.3-2.7-.3' \
              'c-2.7 0-4.4 1.7-4.4 4.6v2.4H7v3.3h2.9V22z"/></svg>'
  }.freeze

  def social_icon(channel)
    SOCIAL_ICONS.fetch(channel).html_safe # static constants above, never user input
  end

  # The green counter box: [big number, label].
  def landing_counter(overview)
    days = overview.days
    case overview.phase
    when :before then [days, t('landing.counter.before', count: days)]
    when :today then [t('landing.counter.today_number'), t('landing.counter.today')]
    when :during then [days, t('landing.counter.during', count: days)]
    when :home then [days, t('landing.counter.home')]
    end
  end

  # The km stats beside the counter: [[big number, label], ...], numbers
  # formatted for the current locale (30.000 in pt, 30,000 in en).
  def landing_km_stats(overview)
    case overview.phase
    when :before, :today
      [[number_with_delimiter(overview.planned_km), t('landing.km.planned')]]
    when :during
      [[number_with_delimiter(overview.driven_km), t('landing.km.driven')],
       ["≈ #{number_with_delimiter(overview.left_km)}", t('landing.km.left')]]
    when :home
      [[number_with_delimiter(overview.driven_km), t('landing.km.total')]]
    end
  end

  # "Today: near X" while underway, the start before, "back home" after.
  def landing_map_caption(overview, map)
    case overview.phase
    when :before, :today then t('landing.map.now_before')
    when :home then t('landing.map.now_after')
    else
      map[:place] ? t('landing.map.now_during', place: map[:place]) : t('landing.map.now_during_unplaced')
    end
  end
end
