# frozen_string_literal: true

require 'test_helper'

class GoogleSignInTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @user = User.create!(email: 'me@example.com')
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def silence_omniauth_logger
    original = OmniAuth.config.logger
    OmniAuth.config.logger = Logger.new(nil)
    yield
  ensure
    OmniAuth.config.logger = original
  end

  def mock_google(email:, verified: true, uid: 'g-123')
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: uid,
      info: { email: email, name: 'Me', image: 'http://x/y.png' },
      extra: { raw_info: { email_verified: verified } }
    )
  end

  test 'anonymous visitors are redirected to login for protected pages' do
    get trips_path
    assert_redirected_to new_user_session_path
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test 'landing and login pages are public' do
    get root_path
    assert_response :success
    get new_user_session_path
    assert_response :success
  end

  test 'registered user signs in and gets trips' do
    mock_google(email: 'Me@Example.com')
    post user_google_oauth2_omniauth_authorize_path
    follow_redirect!
    assert_redirected_to trips_path
    assert_equal 'g-123', @user.reload.uid
    get trips_path
    assert_response :success
  end

  test 'unregistered Google account is rejected and not created' do
    mock_google(email: 'stranger@example.com')
    assert_no_difference 'User.count' do
      post user_google_oauth2_omniauth_authorize_path
      follow_redirect!
    end
    assert_redirected_to new_user_session_path
    get trips_path
    assert_redirected_to new_user_session_path
  end

  test 'unverified Google email is rejected' do
    mock_google(email: 'me@example.com', verified: false)
    post user_google_oauth2_omniauth_authorize_path
    follow_redirect!
    assert_redirected_to new_user_session_path
    assert_nil @user.reload.uid
  end

  test 'a failed or cancelled Google sign-in returns to the login page' do
    OmniAuth.config.mock_auth[:google_oauth2] = :access_denied
    # Devise's own on_failure handler routes this to omniauth_callbacks#failure.
    silence_omniauth_logger { post user_google_oauth2_omniauth_authorize_path }
    follow_redirect!
    assert_redirected_to new_user_session_path
  end

  test 'sign out ends the session' do
    mock_google(email: 'me@example.com')
    post user_google_oauth2_omniauth_authorize_path
    follow_redirect!
    delete destroy_user_session_path
    get trips_path
    assert_redirected_to new_user_session_path
  end
end
