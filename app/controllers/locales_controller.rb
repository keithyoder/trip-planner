# frozen_string_literal: true

class LocalesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:update]

  LOCALE_MAPPING = {
    'pt-BR' => 'pt',
    'en' => 'en',
    'es' => 'es'
  }.freeze

  def update
    locale = params[:locale]&.to_sym

    if I18n.available_locales.include?(locale)
      cookies[:locale] = { value: locale.to_s, expires: 1.year.from_now }
      redirect_back(fallback_location: root_path, notice: "Locale changed to #{locale}")
    else
      redirect_back(fallback_location: root_path, alert: 'Invalid locale')
    end
  end
end
