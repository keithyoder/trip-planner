# app/models/holiday.rb
class Holiday < ApplicationRecord
  belongs_to :boundary

  # Calculation types as enum
  enum :calculation_type, {
    fixed: 0,
    easter_offset: 1,
    movable_uruguay: 2,
    movable_argentina: 3,
    movable_chile: 4
  }

  validates :name, presence: true
  validates :month, :day, presence: true, if: -> { fixed? || movable_type? }
  validates :month, inclusion: { in: 1..12 }, allow_nil: true
  validates :day, inclusion: { in: 1..31 }, allow_nil: true
  validates :offset_days, presence: true, if: :easter_offset?

  validate :valid_date_combination, if: -> { fixed? || movable_type? }

  # Calculate the date for a specific year
  def date_for_year(year) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    case calculation_type.to_sym
    when :fixed
      Date.new(year, month, day)
    when :easter_offset
      easter_date(year) + offset_days.days
    when :movable_uruguay
      apply_uruguay_rules(Date.new(year, month, day))
    when :movable_argentina
      apply_argentina_rules(Date.new(year, month, day))
    when :movable_chile
      apply_chile_rules(Date.new(year, month, day))
    else
      raise "Unknown calculation type: #{calculation_type}"
    end
  end

  # Get all dates for a range of years
  def dates_for_years(start_year, end_year)
    (start_year..end_year).map { |year| { year: year, date: date_for_year(year) } }
  end

  # Check if this holiday occurs on a specific date
  def occurs_on?(date)
    date_for_year(date.year) == date
  end

  # Human-readable description of how this holiday is calculated
  def calculation_description # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    case calculation_type.to_sym
    when :fixed
      "Fecha fija: #{Date::MONTHNAMES[month]} #{day}"
    when :easter_offset
      if offset_days.zero?
        'Domingo de Pascua'
      elsif offset_days.negative?
        "#{offset_days.abs} días antes de Pascua"
      else
        "#{offset_days} días después de Pascua"
      end
    when :movable_uruguay
      "#{Date::MONTHNAMES[month]} #{day} (trasladable - reglas Uruguay)"
    when :movable_argentina
      "#{Date::MONTHNAMES[month]} #{day} (trasladable - reglas Argentina)"
    end
  end

  private

  # Helper to check if this is any movable type
  def movable_type?
    movable_uruguay? || movable_argentina?
  end

  def valid_date_combination
    return unless month && day

    begin
      Date.new(2024, month, day) # Use leap year to allow Feb 29
    rescue ArgumentError
      errors.add(:base, "Combinación de fecha inválida: mes #{month}, día #{day}")
    end
  end

  # Calculate Easter Sunday for a given year using Computus algorithm
  def easter_date(year) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    a = year % 19
    b = year / 100
    c = year % 100
    d = b / 4
    e = b % 4
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i = c / 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month = (h + l - 7 * m + 114) / 31
    day = ((h + l - 7 * m + 114) % 31) + 1

    Date.new(year, month, day)
  end

  # Uruguay: Tue/Wed -> previous Mon, Thu/Fri -> next Mon, Sat/Sun unchanged
  def apply_uruguay_rules(date) # rubocop:disable Metrics/MethodLength
    case date.wday
    when 0 # Sunday
      date
    when 1 # Monday
      date
    when 2, 3 # Tuesday or Wednesday
      date - (date.wday - 1).days # Move to previous Monday
    when 4, 5 # Thursday or Friday
      date + (8 - date.wday).days # Move to next Monday
    when 6 # Saturday
      date
    else
      date
    end
  end

  # Argentina: Tue/Wed -> previous Mon, Sat/Sun -> next Mon, Thu/Fri unchanged
  def apply_argentina_rules(date) # rubocop:disable Metrics/MethodLength
    case date.wday
    when 0 # Sunday
      date + 1.day # Move to Monday
    when 1 # Monday
      date
    when 2, 3 # Tuesday or Wednesday
      date - (date.wday - 1).days # Move to previous Monday
    when 4, 5 # Thursday or Friday
      date # Keep on original day
    when 6 # Saturday
      date + 2.days # Move to Monday
    else
      date
    end
  end

  # Chile: Tue/Wed/Thu -> previous Mon, Fri -> next Mon
  def apply_chile_rules(date) # rubocop:disable Metrics/MethodLength
    case date.wday
    when 0 # Sunday
      date # Keep on Sunday
    when 1 # Monday
      date # Keep on Monday
    when 2, 3, 4 # Tuesday, Wednesday, or Thursday
      date - (date.wday - 1).days # Move to previous Monday
    when 5 # Friday
      date + 3.days # Move to next Monday
    when 6 # Saturday
      date # Keep on Saturday
    else
      date
    end
  end
end
