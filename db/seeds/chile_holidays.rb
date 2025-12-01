# frozen_string_literal: true

# Chile National Holidays
chile = Boundary.find_by(level: 2, name: 'Chile')

puts "Creating holidays for #{chile.name}..."

holidays = [
  # Fixed holidays
  {
    name: 'Año Nuevo',
    calculation_type: :fixed,
    month: 1,
    day: 1
  },
  {
    name: 'Día del Trabajo',
    calculation_type: :fixed,
    month: 5,
    day: 1
  },
  {
    name: 'Día Nacional de los Pueblos Indígenas',
    calculation_type: :fixed,
    month: 6,
    day: 21 # Winter Solstice - honoring indigenous peoples
  },
  {
    name: 'Virgen del Carmen',
    calculation_type: :fixed,
    month: 7,
    day: 16
  },
  {
    name: 'Asunción de la Virgen',
    calculation_type: :fixed,
    month: 8,
    day: 15
  },
  {
    name: 'Independencia Nacional',
    calculation_type: :fixed,
    month: 9,
    day: 18
  },
  {
    name: 'Día de las Glorias del Ejército',
    calculation_type: :fixed,
    month: 9,
    day: 19
  },
  {
    name: 'Inmaculada Concepción',
    calculation_type: :fixed,
    month: 12,
    day: 8
  },
  {
    name: 'Navidad',
    calculation_type: :fixed,
    month: 12,
    day: 25
  },

  # Movable holidays - Chile has special rules:
  # Move to preceding Monday if Tue/Wed/Thu, or following Monday if Fri
  {
    name: 'San Pedro y San Pablo',
    calculation_type: :movable_chile,
    month: 6,
    day: 29
  },
  {
    name: 'Encuentro de Dos Mundos',
    calculation_type: :movable_chile,
    month: 10,
    day: 12
  },
  {
    name: 'Día de las Iglesias Evangélicas y Protestantes',
    calculation_type: :movable_chile,
    month: 10,
    day: 31 # Reformation Day
  },

  # Easter-based holidays
  {
    name: 'Viernes Santo',
    calculation_type: :easter_offset,
    offset_days: -2
  },
  {
    name: 'Sábado Santo',
    calculation_type: :easter_offset,
    offset_days: -1
  }
]

holidays.each do |holiday_data|
  holiday = Holiday.find_or_initialize_by(
    boundary: chile,
    name: holiday_data[:name]
  )

  holiday.assign_attributes(
    calculation_type: holiday_data[:calculation_type],
    month: holiday_data[:month],
    day: holiday_data[:day],
    offset_days: holiday_data[:offset_days] || 0
  )

  if holiday.save
    puts "  ✓ #{holiday.name}"
  else
    puts "  ✗ #{holiday.name}: #{holiday.errors.full_messages.join(', ')}"
  end
end

puts "\nChile holidays created: #{chile.holidays.count}"
puts "\nSample dates for 2027:"
chile.holidays.sort_by { |h| h.date_for_year(2027) }.each do |holiday|
  date = holiday.date_for_year(2027)
  puts "  #{date.strftime('%a, %b %d, %Y')} - #{holiday.name}"
end
