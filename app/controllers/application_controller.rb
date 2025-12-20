# frozen_string_literal: true

class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_locale

  def set_locale
    cookie_locale = locale_from_cookies

    header_locale = extract_locale_from_accept_language_header

    I18n.locale = cookie_locale ||
                  header_locale ||
                  I18n.default_locale

    # Store the determined locale in cookies for next request
    cookies[:locale] = { value: I18n.locale.to_s, expires: 1.year.from_now }
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end

  def after_sign_in_path_for(_resource)
    trips_path
  end

  private

  def locale_from_cookies
    locale = cookies[:locale]&.to_sym
    return locale if I18n.available_locales.include?(locale)

    nil
  end

  def extract_locale_from_accept_language_header
    return nil unless request.env['HTTP_ACCEPT_LANGUAGE']

    accepted_locales = request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^[a-z]{2}/).map(&:to_sym)
    (accepted_locales & I18n.available_locales).first
  end
end
