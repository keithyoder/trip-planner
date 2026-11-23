# frozen_string_literal: true

require 'test_helper'

module Landing
  class TripPhaseTest < ActiveSupport::TestCase
    START = Date.new(2027, 1, 30)

    def phase_for(today, status: :planning)
      TripPhase.new(Trip.new(start_on: START, status: status), today: today)
    end

    test 'counts down to the start before leaving' do
      p = phase_for(Date.new(2027, 1, 20))
      assert_equal :before, p.phase
      assert_equal 10, p.days
    end

    test 'the day before the start is one day out' do
      p = phase_for(START - 1)
      assert_equal :before, p.phase
      assert_equal 1, p.days
    end

    test 'the start day is its own state' do
      assert_equal :today, phase_for(START).phase
    end

    test 'the first day after the start is day 2, the start day being day 1' do
      p = phase_for(START + 1, status: :in_progress)
      assert_equal :during, p.phase
      assert_equal 2, p.days
    end

    test 'stays in during until the trip is flagged completed, however long it runs' do
      p = phase_for(START + 200, status: :in_progress)
      assert_equal :during, p.phase
      assert_equal 201, p.days
    end

    test 'completed means home, whatever the date, and keeps the day count' do
      p = phase_for(START + 115, status: :completed)
      assert_equal :home, p.phase
      assert_equal 116, p.days
    end

    test 'a completed trip never reports a day below 1' do
      assert_equal 1, phase_for(START - 5, status: :completed).days
    end

    test 'today is counted in Pesqueira, not the server zone' do
      # 01:30 UTC on 30 Jan is still 29 Jan in Recife (UTC-3).
      travel_to Time.utc(2027, 1, 30, 1, 30) do
        assert_equal Date.new(2027, 1, 29), TripPhase.today
      end
    end
  end
end
