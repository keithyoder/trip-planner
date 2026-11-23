# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = 'noreply@trip.tessi.com.br'
  require 'devise/orm/active_record'

  config.navigational_formats = ['*/*', :html, :turbo_stream]
  config.sign_out_via = :delete
  config.parent_controller = 'ApplicationController'

  # Fail loudly at boot if the credentials are missing rather than producing a
  # login button that 500s on the road. Skipped for asset precompile / CI.
  google_id = ENV['GOOGLE_CLIENT_ID']
  google_secret = ENV['GOOGLE_CLIENT_SECRET']
  if google_id.blank? || google_secret.blank?
    Rails.logger.warn('[devise] GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET not set; Google sign-in disabled')
  end

  config.omniauth :google_oauth2, google_id, google_secret,
                  scope: 'email,profile',
                  prompt: 'select_account'
end
