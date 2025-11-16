# frozen_string_literal: true

module LocalesHelper
  LOCALE_FLAGS = {
    'en' => 'us',
    'es' => 'es',
    'pt' => 'br'
  }.freeze

  def locale_flag(locale)
    LOCALE_FLAGS[locale.to_s] || 'us'
  end

  def current_locale_flag
    locale_flag(I18n.locale)
  end
end
