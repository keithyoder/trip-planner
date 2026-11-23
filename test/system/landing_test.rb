# frozen_string_literal: true

require 'application_system_test_case'

# The public landing and login pages in a real browser: the language switch and
# its cookie, a failed sign-in, and being sent to the login and back.
class LandingTest < ApplicationSystemTestCase
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def locale_cookie
    page.driver.browser.manage.cookie_named('locale')&.dig(:value)
  end

  # Reads the heading with a script instead of a found element. Right after a
  # language button reloads the page, Chrome can answer "Node with given id does
  # not belong to the document" for an element found a moment earlier; Capybara
  # only retries stale-element errors, so that one failed the test now and then
  # (seen on CI). A script runs in whatever document is current, so just retry it
  # until the page has settled.
  def assert_headline(expected)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
    actual = nil
    loop do
      actual = current_headline
      break if actual == expected || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
    assert_equal expected, actual
  end

  def current_headline
    page.evaluate_script("(document.querySelector('h1') || {}).textContent")
  rescue Selenium::WebDriver::Error::WebDriverError
    nil # mid-navigation
  end

  def mock_google(email:, uid: 'g-1')
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: uid, info: { email: email, name: 'Tester' },
      extra: { raw_info: { email_verified: true } }
    )
  end

  test 'the language switch changes the page, sets the cookie and is remembered' do
    visit root_path(lang: 'pt')
    assert_headline 'Quatro meses, cinco países e o Mocó.'

    within('header') { click_button 'EN' }
    assert_headline 'Four months, five countries and the Mocó.'
    assert_equal 'en', locale_cookie

    visit root_path # a later visit, no param: the cookie decides
    assert_headline 'Four months, five countries and the Mocó.'

    within('header') { click_button 'PT' }
    assert_headline 'Quatro meses, cinco países e o Mocó.'
    assert_equal 'pt', locale_cookie

    within('header') { click_button 'ES' }
    assert_headline 'Cuatro meses, cinco países y el Mocó.'
    assert_equal 'es', locale_cookie
  end

  test '?lang= sets the language and leaves a clean URL' do
    visit root_path(lang: 'en')

    assert_current_path root_path
    assert_selector 'html[lang="en"]'
    assert_equal 'en', locale_cookie
  end

  test 'a failed sign-in shows the red alert box and keeps the form usable' do
    mock_google(email: 'stranger@example.com')
    visit new_user_session_path(lang: 'en')

    click_button 'Sign in with Google'

    assert_current_path new_user_session_path
    assert_selector '.alert[role="alert"]', text: 'stranger@example.com is not registered for this app.'
    assert_button 'Sign in with Google'
  end

  test 'a restricted page sends you to the login and signing in brings you back' do
    User.create!(email: 'invited@example.com', role: :admin)
    mock_google(email: 'invited@example.com')

    visit new_trip_path
    assert_current_path new_user_session_path

    click_button 'Entrar com o Google' if page.has_button?('Entrar com o Google')
    click_button 'Sign in with Google' if page.has_button?('Sign in with Google')

    assert_current_path new_trip_path
  end

  test 'the home page reads right at a phone width: nothing wider than the screen' do
    page.driver.browser.manage.window.resize_to(520, 1000)
    visit root_path(lang: 'en')

    overflow = page.evaluate_script('document.documentElement.scrollWidth > document.documentElement.clientWidth')
    assert_not overflow, 'the page scrolls sideways'
    assert_selector '.stat-count'
  end
end
