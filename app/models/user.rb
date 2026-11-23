# frozen_string_literal: true

# Invite-only: a row must already exist (created from the console) for a Google
# account to sign in. There is deliberately no sign-up path, and no password
# columns, so Google is the only way in.
class User < ApplicationRecord
  devise :omniauthable, :trackable, omniauth_providers: %i[google_oauth2]

  # Explicit integer keys: these are stored, so they must never shift.
  enum :role, { viewer: 0, admin: 1 }

  validates :email, presence: true, uniqueness: true

  # Matches on the stable Google uid once linked, falling back to email for the
  # first sign-in of a pre-registered user. Returns nil for anyone unregistered;
  # never creates a user.
  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid) ||
           find_by(email: auth.info.email.to_s.downcase)
    user&.tap { |u| u.link_google!(auth) }
  end

  def link_google!(auth)
    update!(provider: auth.provider, uid: auth.uid,
            name: name.presence || auth.info.name, avatar_url: auth.info.image)
  end
end
