# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :locale

    def connect
      self.locale = determine_locale
    end

    private

    def determine_locale
      candidate = cookies[:locale]&.to_sym
      I18n.available_locales.include?(candidate) ? candidate : I18n.default_locale
    end
  end
end
