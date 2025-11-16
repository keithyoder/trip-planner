class LocalesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:update]

  LOCALE_MAPPING = {
    'pt-BR' => 'pt',
    'en' => 'en',
    'es' => 'es'
  }.freeze

  def update
    locale = LOCALE_MAPPING[params[:locale]] || params[:locale]

    Rails.logger.debug "Before: session[:locale] = #{session[:locale]}"

    if I18n.available_locales.map(&:to_s).include?(locale)
      session[:locale] = locale
      I18n.locale = locale

      Rails.logger.debug "After: session[:locale] = #{session[:locale]}"

      redirect_back_or_to(root_path, allow_other_host: false)
    else
      redirect_back(fallback_location: root_path, alert: t('locale.invalid'))
    end
  end
end
