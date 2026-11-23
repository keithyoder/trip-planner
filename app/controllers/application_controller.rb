# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Before authentication so a ?lang= link works even on pages that send an
  # anonymous visitor to the login first.
  before_action :apply_lang_param
  before_action :authenticate_user!
  # Fail closed: every controller is admin-only unless it opts out, so a new
  # controller can never expose editing to viewers by being forgotten.
  before_action :require_admin!
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

  # Back to the page that required sign-in (Devise stores it when it sends an
  # anonymous visitor to /login), otherwise the trip list.
  def after_sign_in_path_for(resource)
    stored_location_for(resource) || home_path_for(resource)
  end

  # Admins work in the planner; viewers only ever see the read-only pages.
  def home_path_for(user)
    user.admin? ? trips_path : follow_path
  end
  helper_method :home_path_for

  def require_admin!
    return if devise_controller? # Devise's own screens (the OAuth callback) run signed out
    return if current_user&.admin?

    redirect_to follow_path
  end

  private

  # ?lang=pt|pt-BR|en|es stores the choice in the locale cookie, then redirects
  # to the same URL without the param. Redirecting matters: otherwise a stale
  # ?lang=en would keep overriding a later switch made with the language buttons,
  # because those redirect back to the page they were clicked on.
  def apply_lang_param
    return unless request.get? && params.key?(:lang)

    locale = lang_param_locale
    cookies[:locale] = { value: locale.to_s, expires: 1.year.from_now } if locale
    redirect_to path_without_lang_param
  end

  def path_without_lang_param
    query = request.query_parameters.except('lang').to_query
    [request.path, query.presence].compact.join('?')
  end

  def lang_param_locale
    candidate = params[:lang].to_s.downcase.sub(/\Apt-br\z/, 'pt').to_sym
    candidate if I18n.available_locales.include?(candidate)
  end

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
