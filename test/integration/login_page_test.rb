# frozen_string_literal: true

require 'test_helper'

# The login screen: a Google button, because sign-in is Google-only and
# invite-only (see google_sign_in_test.rb for the flows themselves).
class LoginPageTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    cookies[:locale] = 'pt'
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test 'shows the Google button, the invite note and a way back' do
    get new_user_session_path

    assert_response :success
    assert_select 'h1', 'Entrar'
    assert_select 'form[action=?][method="post"] button',
                  user_google_oauth2_omniauth_authorize_path, 'Entrar com o Google'
    assert_select 'a.back[href=?]', root_path, /Voltar ao início/
    assert_select '.login-sub', 'O diário da viagem e o rastreio ao vivo são para quem foi convidado.'
    assert_select '[role="alert"]', 0
  end

  test 'has no password fields: sign-in is Google only' do
    get new_user_session_path

    assert_select 'input[type="password"]', 0
    assert_select 'input[type="email"]', 0
  end

  test 'the header has the language switch but no login button' do
    get new_user_session_path

    assert_select '.lang-btn', 3
    assert_select 'header a.btn-primary', 0
  end

  test 'a failed sign-in shows the red alert box with the reason' do
    OmniAuth.config.mock_auth[:google_oauth2] = :access_denied
    original = OmniAuth.config.logger
    OmniAuth.config.logger = Logger.new(nil)
    post user_google_oauth2_omniauth_authorize_path
    OmniAuth.config.logger = original
    follow_redirect! # the OmniAuth callback
    follow_redirect! # back to the login page, with the alert

    assert_select '.alert[role="alert"] strong', 'Não foi possível entrar.'
    assert_select '.alert[role="alert"] span', 'O login com o Google falhou ou foi cancelado.'
  end

  test 'an uninvited Google account is told so, in English when the locale is English' do
    cookies[:locale] = 'en'
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'x', info: { email: 'stranger@example.com' },
      extra: { raw_info: { email_verified: true } }
    )
    post user_google_oauth2_omniauth_authorize_path
    follow_redirect! # the OmniAuth callback
    follow_redirect! # back to the login page, with the alert

    assert_select 'html[lang="en"]'
    assert_select '.alert[role="alert"] strong', "We couldn't log you in."
    assert_select '.alert[role="alert"] span', 'stranger@example.com is not registered for this app.'
  end

  test 'a signed-in user is sent on to the app' do
    sign_in User.create!(email: 'in@example.com')
    get new_user_session_path

    assert_redirected_to trips_path
  end
end
