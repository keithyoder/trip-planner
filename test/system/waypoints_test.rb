# frozen_string_literal: true

require 'application_system_test_case'

class WaypointsTest < ApplicationSystemTestCase
  setup do
    @waypoint = waypoints(:one)
  end

  test 'visiting the index' do
    visit waypoints_url
    assert_selector 'h1', text: 'Waypoints'
  end

  test 'should create waypoint' do
    visit waypoints_url
    click_on 'New waypoint'

    fill_in 'Name', with: @waypoint.name
    fill_in 'Sequence', with: @waypoint.sequence
    click_on 'Create Waypoint'

    assert_text 'Waypoint was successfully created'
    click_on 'Back'
  end

  test 'should update Waypoint' do
    visit waypoint_url(@waypoint)
    click_on 'Edit this waypoint', match: :first

    fill_in 'Name', with: @waypoint.name
    fill_in 'Sequence', with: @waypoint.sequence
    click_on 'Update Waypoint'

    assert_text 'Waypoint was successfully updated'
    click_on 'Back'
  end

  test 'should destroy Waypoint' do
    visit waypoint_url(@waypoint)
    click_on 'Destroy this waypoint', match: :first

    assert_text 'Waypoint was successfully destroyed'
  end
end
