# frozen_string_literal: true

# Bolivia National Holidays
bolivia = Boundary.find_by(level: 2, name: 'Bolivia')

puts "Creating holidays for #{bolivia.name}..."

holidays = [
  # Fixed national holidays
  {
    name: 'Año Nuevo',
    calculation_type: :fixed,
    month: 1,
    day: 1
  },
  {
    name: 'Día de la Fundación del Estado Plurinacional',
    calculation_type: :fixed,
    month: 1,
    day: 22
  },
  {
    name: 'Día del Mar',
    calculation_type: :fixed,
    month: 3,
    day: 23
  },
  {
    name: 'Día del Trabajo',
    calculation_type: :fixed,
    month: 5,
    day: 1
  },
  {
    name: 'Año Nuevo Aymara',
    calculation_type: :fixed,
    month: 6,
    day: 21 # Winter Solstice - Aymara New Year
  },
  {
    name: 'Día de la Independencia',
    calculation_type: :fixed,
    month: 8,
    day: 6
  },
  {
    name: 'Día de Todos los Santos',
    calculation_type: :fixed,
    month: 11,
    day: 2
  },
  {
    name: 'Navidad',
    calculation_type: :fixed,
    month: 12,
    day: 25
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
    name: 'Viernes Santo',
    calculation_type: :easter_offset,
    offset_days: -2
  },
  {
    name: 'Corpus Christi',
    calculation_type: :easter_offset,
    offset_days: 60
  }
]

holidays.each do |holiday_data|
  holiday = Holiday.find_or_initialize_by(
    boundary: bolivia,
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

puts "\nBolivia holidays created: #{bolivia.holidays.count}"
puts "\nSample dates for 2027:"
bolivia.holidays.sort_by { |h| h.date_for_year(2027) }.each do |holiday|
  date = holiday.date_for_year(2027)
  puts "  #{date.strftime('%a, %b %d, %Y')} - #{holiday.name}"
end

# db/seeds/bolivia_departmental_holidays.rb
# Bolivia Departmental/Regional Holidays
# Each of Bolivia's 9 departments has one regional holiday

puts 'Creating departmental holidays for Bolivia...'

# Department holidays mapping
departmental_holidays = {
  'Chuquisaca' => { name: 'Día de Chuquisaca', month: 5, day: 25 },
  'La Paz' => { name: 'Día de La Paz', month: 7, day: 16 },
  'Cochabamba' => { name: 'Día de Cochabamba', month: 9, day: 14 },
  'Oruro' => { name: 'Día de Oruro', month: 2, day: 10 },
  'Potosí' => { name: 'Día de Potosí', month: 11, day: 10 },
  'Tarija' => { name: 'Día de Tarija', month: 4, day: 15 },
  'Santa Cruz' => { name: 'Día de Santa Cruz', month: 9, day: 24 },
  'Beni' => { name: 'Día del Beni', month: 11, day: 18 },
  'Pando' => { name: 'Día de Pando', month: 9, day: 24 }
}

departmental_holidays.each do |department_name, holiday_data|
  # Find the department boundary
  department = Boundary.find_by(level: 4, name: department_name)

  if department.nil?
    puts "  ⚠ Department '#{department_name}' not found, skipping..."
    next
  end

  holiday = Holiday.find_or_initialize_by(
    boundary: department,
    name: holiday_data[:name]
  )

  holiday.assign_attributes(
    calculation_type: :fixed,
    month: holiday_data[:month],
    day: holiday_data[:day],
    offset_days: 0
  )

  if holiday.save
    puts "  ✓ #{department_name}: #{holiday.name} (#{Date::MONTHNAMES[holiday_data[:month]]} #{holiday_data[:day]})"
  else
    puts "  ✗ #{department_name}: #{holiday.errors.full_messages.join(', ')}"
  end
end
