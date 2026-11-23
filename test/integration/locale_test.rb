# frozen_string_literal: true

require 'test_helper'

# The public pages share the app's existing `locale` cookie; ?lang= is the
# link-friendly way to set it.
class LocaleTest < ActionDispatch::IntegrationTest
  test 'lang param sets the locale cookie and redirects to the clean URL' do
    get '/login', params: { lang: 'en' }

    assert_redirected_to '/login'
    assert_equal 'en', cookies[:locale]
  end

  test 'pt-BR is accepted and maps to the pt locale' do
    get '/login', params: { lang: 'pt-BR' }

    assert_redirected_to '/login'
    assert_equal 'pt', cookies[:locale]
  end

  test 'other query params survive the redirect' do
    get '/login', params: { lang: 'es', ref: 'x' }

    assert_redirected_to '/login?ref=x'
    assert_equal 'es', cookies[:locale]
  end

  test 'an unsupported lang is ignored but still stripped from the URL' do
    get '/login', params: { lang: 'xx' }

    assert_redirected_to '/login'
    assert_not_equal 'xx', cookies[:locale]
  end

  test 'lang works on a protected page before the login redirect' do
    get '/trips', params: { lang: 'en' }
    assert_redirected_to '/trips'
    assert_equal 'en', cookies[:locale]

    follow_redirect!
    assert_redirected_to new_user_session_path
  end

  test 'a later language switch is not overridden by a stale lang param' do
    get '/login', params: { lang: 'en' }
    post locale_path(locale: 'pt')

    assert_equal 'pt', cookies[:locale]
  end
end
