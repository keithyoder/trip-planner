# frozen_string_literal: true

# Uruguay National Holidays
uruguay = Boundary.find(3)

puts "Creating holidays for #{uruguay.name}..."

holidays = [
  # Fixed holidays (non-movable)
  {
    name: 'Año Nuevo',
    calculation_type: :fixed,
    month: 1,
    day: 1
  },
  {
    name: 'Día de los Reyes',
    calculation_type: :fixed,
    month: 1,
    day: 6
  },
  {
    name: 'Día Internacional de los Trabajadores',
    calculation_type: :fixed,
    month: 5,
    day: 1
  },
  {
    name: 'Natalicio de Artigas y Día del Nunca Más',
    calculation_type: :fixed,
    month: 6,
    day: 19
  },
  {
    name: 'Jura de la Constitución',
    calculation_type: :fixed,
    month: 7,
    day: 18
  },
  {
    name: 'Declaratoria de la Independencia',
    calculation_type: :fixed,
    month: 8,
    day: 25
  },
  {
    name: 'Día de los Difuntos',
    calculation_type: :fixed,
    month: 11,
    day: 2
  },
  {
    name: 'Día de la Familia',
    calculation_type: :fixed,
    month: 12,
    day: 25
  },

  # Movable holidays (moved to Monday for long weekends)
  {
    name: 'Desembarco de los 33 Orientales',
    calculation_type: :movable_uruguay,
    month: 4,
    day: 19
  },
  {
    name: 'Batalla de Las Piedras',
    calculation_type: :movable_uruguay,
    month: 5,
    day: 18
  },
  {
    name: 'Día de la Raza',
    calculation_type: :movable_uruguay,
    month: 10,
    day: 12
  },

  # Easter-based holidays
  {
    name: 'Carnaval (Lunes)',
    calculation_type: :easter_offset,
    offset_days: -48
  },
  {
    name: 'Carnaval (Martes)',
    calculation_type: :easter_offset,
    offset_days: -47
  },
  {
    name: 'Jueves Santo',
    calculation_type: :easter_offset,
    offset_days: -3
  },
  {
    name: 'Viernes Santo',
    calculation_type: :easter_offset,
    offset_days: -2
  }
]

holidays.each do |holiday_data|
  holiday = Holiday.find_or_initialize_by(
    boundary: uruguay,
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

puts "\nUruguay holidays created: #{uruguay.holidays.count}"
puts "\nSample dates for 2027:"
uruguay.holidays.order(:calculation_type, :month, :day).each do |holiday|
  date = holiday.date_for_year(2027)
  puts "  #{date.strftime('%a, %b %d, %Y')} - #{holiday.name}"
end
