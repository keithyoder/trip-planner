# frozen_string_literal: true

# Helpers for the public pages (landing and login), which use their own layout.
module PublicHelper
  # <html lang> wants a BCP 47 tag; the app's Portuguese locale is plain :pt but
  # the audience is Brazilian.
  HTML_LANGS = { pt: 'pt-BR', en: 'en', es: 'es' }.freeze

  def public_html_lang
    HTML_LANGS.fetch(I18n.locale, I18n.locale.to_s)
  end

  # The PT | EN switch only offers the two languages the design covers. Spanish
  # still works (cookie or Accept-Language) and simply shows neither pressed.
  def public_language_choices
    [%w[pt PT Português], %w[en EN English]]
  end
end
