# frozen_string_literal: true

# == Schema Information
#
# Table name: stops
#
#  id         :bigint           not null, primary key
#  trip_id    :bigint           not null
#  name       :string
#  stop_type  :integer          not null
#  start_time :datetime         not null
#  end_time   :datetime         not null
#  geom       :geography        point, 4326
#  notes      :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Stop < ApplicationRecord
  belongs_to :trip
  has_many :expenses, dependent: :destroy

  # Reuses Waypoint's exact type set (and therefore its integer mapping,
  # icons, colors, and i18n keys) rather than maintaining a second list
  # that could drift -- a stop and a waypoint mean the same thing
  # ("something happened here"), just one is planned and one is detected.
  enum :stop_type, Waypoint.waypoint_types, default: :routing

  validates :start_time, :end_time, :geom, presence: true
  validate :end_time_after_start_time

  scope :on_date, ->(date) { where('start_time >= ? AND start_time < ?', date.beginning_of_day, date.end_of_day) }
  scope :recent, -> { order(start_time: :asc) }

  def duration
    (end_time - start_time).to_i
  end

  def duration_minutes
    (duration / 60.0).round(1)
  end

  def location
    return nil unless geom

    { lat: geom.y, lon: geom.x }
  end

  def display_name
    name.presence || I18n.t("waypoints.#{stop_type}")
  end

  # Mirrors Waypoint#currency -- derives the likely currency from the
  # country boundary containing this stop, so an expense form can default
  # to something sensible instead of always guessing the trip's home
  # currency.
  def currency
    CountryCurrency.for(country)
  end

  def country
    return nil unless geom

    Boundary.containing_point(geom.y, geom.x).where(level: 2).pick(:name)
  end

  # total_by_category / total_amount depend on Expense, added separately --
  # see has_many :expenses above. Left out here until that table/model
  # exist so this file doesn't reference something that isn't there yet.

  private

  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?

    errors.add(:end_time, 'must be after start time') if end_time <= start_time
  end
end
