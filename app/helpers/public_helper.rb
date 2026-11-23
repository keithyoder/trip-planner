# frozen_string_literal: true

# Helpers for the public pages (landing and login), which use their own layout.
module PublicHelper
  # <html lang> wants a BCP 47 tag; the app's Portuguese locale is plain :pt but
  # the audience is Brazilian.
  HTML_LANGS = { pt: 'pt-BR', en: 'en', es: 'es' }.freeze

  def public_html_lang
    HTML_LANGS.fetch(I18n.locale, I18n.locale.to_s)
  end

  # The PT | EN | ES switch: code, button label, and the language's own name
  # (used as the accessible label).
  def public_language_choices
    [%w[pt PT Português], %w[en EN English], %w[es ES Español]]
  end
end
