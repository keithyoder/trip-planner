# frozen_string_literal: true

module Users
  # Handles the Google OAuth round trip. Sign-in is invite-only: the Google
  # account's email must already belong to a User row.
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      auth = request.env['omniauth.auth']
      return reject(t('auth.unverified_email')) unless email_verified?(auth)

      user = User.from_omniauth(auth)
      return reject_unregistered(auth.info.email) unless user

      sign_out_all_scopes
      flash[:notice] = t('auth.signed_in')
      sign_in_and_redirect user, event: :authentication
    end

    def failure
      reject(t('auth.failed'))
    end

    private

    # Google accounts can carry an unverified email; matching on it would let
    # someone claim a registered address.
    def email_verified?(auth)
      auth.extra&.raw_info&.email_verified
    end

    def reject(message)
      redirect_to new_user_session_path, alert: message
    end

    def reject_unregistered(email)
      Rails.logger.warn("[auth] rejected unregistered Google account #{email}")
      reject(t('auth.not_registered', email: email))
    end
  end
end
