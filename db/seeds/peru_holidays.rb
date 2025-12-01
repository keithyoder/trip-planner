# frozen_string_literal: true

# Peru National Holidays
peru = Boundary.find_by(level: 2, name: 'Perú')
puts "Creating holidays for #{peru.name}..."

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
    name: 'Batalla de Arica y Día de la Bandera',
    calculation_type: :fixed,
    month: 6,
    day: 7
  },
  {
    name: 'Día de San Pedro y San Pablo',
    calculation_type: :fixed,
    month: 6,
    day: 29
  },
  {
    name: 'Día de la Fuerza Aérea del Perú',
    calculation_type: :fixed,
    month: 7,
    day: 23
  },
  {
    name: 'Día de la Independencia',
    calculation_type: :fixed,
    month: 7,
    day: 28
  },
  {
    name: 'Fiestas Patrias',
    calculation_type: :fixed,
    month: 7,
    day: 29
  },
  {
    name: 'Batalla de Junín',
    calculation_type: :fixed,
    month: 8,
    day: 6
  },
  {
    name: 'Día de Santa Rosa de Lima',
    calculation_type: :fixed,
    month: 8,
    day: 30
  },
  {
    name: 'Combate de Angamos',
    calculation_type: :fixed,
    month: 10,
    day: 8
  },
  {
    name: 'Día de Todos los Santos',
    calculation_type: :fixed,
    month: 11,
    day: 1
  },
  {
    name: 'Inmaculada Concepción',
    calculation_type: :fixed,
    month: 12,
    day: 8
  },
  {
    name: 'Batalla de Ayacucho',
    calculation_type: :fixed,
    month: 12,
    day: 9
  },
  {
    name: 'Navidad',
    calculation_type: :fixed,
    month: 12,
    day: 25
  },

  # Easter-based holidays
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
    boundary: peru,
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

puts "\nPeru holidays created: #{peru.holidays.count}"
puts "\nSample dates for 2027:"
peru.holidays.sort_by { |h| h.date_for_year(2027) }.each do |holiday|
  date = holiday.date_for_year(2027)
  puts "  #{date.strftime('%a, %b %d, %Y')} - #{holiday.name}"
end
