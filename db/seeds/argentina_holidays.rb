# frozen_string_literal: true

# Argentina National Holidays
argentina = Boundary.find_by(level: 2, name: 'Argentina')

puts "Creating holidays for #{argentina.name}..."

holidays = [
  # Fixed holidays (standard holidays - no moving)
  {
    name: 'Año Nuevo',
    calculation_type: :fixed,
    month: 1,
    day: 1
  },
  {
    name: 'Día de la Memoria por la Verdad y la Justicia',
    calculation_type: :fixed,
    month: 3,
    day: 24
  },
  {
    name: 'Día del Veterano y de los Caídos en la Guerra de Malvinas',
    calculation_type: :fixed,
    month: 4,
    day: 2
  },
  {
    name: 'Día del Trabajador',
    calculation_type: :fixed,
    month: 5,
    day: 1
  },
  {
    name: 'Día de la Revolución de Mayo',
    calculation_type: :fixed,
    month: 5,
    day: 25
  },
  {
    name: 'Paso a la Inmortalidad del General Manuel Belgrano',
    calculation_type: :fixed,
    month: 6,
    day: 20
  },
  {
    name: 'Día de la Independencia',
    calculation_type: :fixed,
    month: 7,
    day: 9
  },
  {
    name: 'Inmaculada Concepción de María',
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

  # Movable holidays (Argentina rules: Tue/Wed -> previous Mon, Sat/Sun -> next Mon)
  {
    name: 'Paso a la Inmortalidad del General Martín Miguel de Güemes',
    calculation_type: :movable_argentina,
    month: 6,
    day: 17
  },
  {
    name: 'Paso a la Inmortalidad del General José de San Martín',
    calculation_type: :movable_argentina,
    month: 8,
    day: 17
  },
  {
    name: 'Día del Respeto a la Diversidad Cultural',
    calculation_type: :movable_argentina,
    month: 10,
    day: 12
  },
  {
    name: 'Día de la Soberanía Nacional',
    calculation_type: :movable_argentina,
    month: 11,
    day: 20
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
    boundary: argentina,
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

puts "\nArgentina holidays created: #{argentina.holidays.count}"
puts "\nSample dates for 2027:"
argentina.holidays.sort_by { |h| h.date_for_year(2027) }.each do |holiday|
  date = holiday.date_for_year(2027)
  puts "  #{date.strftime('%a, %b %d, %Y')} - #{holiday.name}"
end
