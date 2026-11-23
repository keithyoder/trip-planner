# frozen_string_literal: true

require 'test_helper'

class LandingPageTest < ActionDispatch::IntegrationTest
  include LandingTripHelpers

  START = Date.new(2027, 1, 30)

  setup do
    Trip.destroy_all
    @trip = Trip.create!(name: 'Landing trip', start_on: START)
    cookies[:locale] = 'pt'
  end

  def recife(year, month, day)
    Time.find_zone!('America/Recife').local(year, month, day, 12)
  end

  def landing_on(time)
    travel_to(time) { get root_path }
    assert_response :success
  end

  test 'renders for anonymous visitors in Portuguese by default, with the start date and no end date' do
    landing_on recife(2026, 12, 1)

    assert_select 'html[lang="pt-BR"]'
    assert_select 'h1', 'Quatro meses, cinco países e o Mocó.'
    assert_select '.eyebrow', 'Saída em 30 de janeiro de 2027 · Pesqueira, PE'
    assert_match 'voltamos em maio', response.body
  end

  test 'English via the existing locale cookie' do
    cookies[:locale] = 'en'
    landing_on recife(2026, 12, 1)

    assert_select 'html[lang="en"]'
    assert_select '.eyebrow', 'Leaving 30 January 2027 · Pesqueira, Pernambuco'
    assert_select 'h1', 'Four months, five countries and the Mocó.'
  end

  test 'Spanish works too, even though the switch only offers PT and EN' do
    cookies[:locale] = 'es'
    landing_on recife(2026, 12, 1)

    assert_select 'html[lang="es"]'
    assert_select 'h1', 'Cuatro meses, cinco países y el Mocó.'
    assert_select '.lang-btn[aria-pressed="true"]', 0
  end

  test 'the language buttons mark the current language and switch it' do
    landing_on recife(2026, 12, 1)
    assert_select '.lang-btn[lang="pt"][aria-pressed="true"]'
    assert_select '.lang-btn[lang="en"][aria-pressed="false"]'

    post locale_path(locale: 'en')
    assert_equal 'en', cookies[:locale]
    follow_redirect!
    assert_select 'html[lang="en"]'
    assert_select '.lang-btn[lang="en"][aria-pressed="true"]'
  end

  test 'follow links open in a new tab, one per channel' do
    landing_on recife(2026, 12, 1)

    assert_select 'a.social[target="_blank"][rel="noopener"]', 4
    %w[Substack Instagram YouTube Facebook].each { |name| assert_select 'a.social .social-name', name }
  end

  test 'the map is server-rendered with the route and a labelled image role' do
    landing_on recife(2026, 12, 1)

    assert_select 'figure.map svg[role="img"][aria-label]'
    assert_select 'figure.map svg circle', 2
  end

  test 'anonymous visitors see the login button and the invite note' do
    landing_on recife(2026, 12, 1)

    assert_select 'header a.btn-primary[href=?]', new_user_session_path, 'Entrar'
    assert_select 'p.invited a[href=?]', new_user_session_path
  end

  test 'signed-in visitors get a way into the app instead' do
    sign_in User.create!(email: 'in@example.com')
    landing_on recife(2026, 12, 1)

    assert_select 'header a.btn-primary[href=?]', trips_path, 'Abrir a viagem'
    assert_select 'p.invited', 0
  end

  test 'loads without Bootstrap or the app stylesheet' do
    landing_on recife(2026, 12, 1)

    assert_select 'link[rel="stylesheet"][href*="public"]'
    assert_select 'link[rel="stylesheet"][href*="application"]', 0
  end
end
