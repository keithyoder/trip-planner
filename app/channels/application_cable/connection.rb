# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :locale, :current_user

    def connect
      self.current_user = find_verified_user
      self.locale = determine_locale
    end

    private

    # Reuses the Warden session from the login cookie. The dashboard stream
    # carries live position, so unauthenticated sockets are refused outright.
    def find_verified_user
      env['warden']&.user(:user) || reject_unauthorized_connection
    end

    def determine_locale
      candidate = cookies[:locale]&.to_sym
      I18n.available_locales.include?(candidate) ? candidate : I18n.default_locale
    end
  end
end
