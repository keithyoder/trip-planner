# frozen_string_literal: true

# db/seeds/brazil_holidays.rb
# Brazil National Holidays for 2027
#
# Brazil has 11 official federal (national) holidays
# Easter 2027: March 28
#
# Sources:
# - https://www.timeanddate.com/holidays/brazil/2027
# - https://en.wikipedia.org/wiki/Public_holidays_in_Brazil
# - Federal Law 662/1949 and Law 9.093/1995
#
# Note: Carnival is technically optional (ponto facultativo) at federal level but
# widely observed. Good Friday and Corpus Christi status varies by municipality.

# Find Brazil boundary
brazil = Boundary.find_by(level: 2, name: 'Brasil')
puts 'Creating Brazil national holidays...'

holidays = [
  # Fixed Date Holidays
  {
    name: 'Confraternização Universal',
    month: 1,
    day: 1,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Dia de Tiradentes',
    month: 4,
    day: 21,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Dia do Trabalho',
    month: 5,
    day: 1,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Dia da Independência',
    month: 9,
    day: 7,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Nossa Senhora Aparecida',
    month: 10,
    day: 12,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Dia de Finados',
    month: 11,
    day: 2,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Proclamação da República',
    month: 11,
    day: 15,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Consciência Negra',
    month: 11,
    day: 20,
    calculation_type: :fixed,
    offset_days: 0
  },
  {
    name: 'Natal',
    month: 12,
    day: 25,
    calculation_type: :fixed,
    offset_days: 0
  },

  # Easter-based Holidays
  {
    name: 'Carnaval (Segunda-feira)',
    calculation_type: :easter_offset,
    offset_days: -48  # 48 days before Easter
  },
  {
    name: 'Carnaval (Terça-feira)',
    calculation_type: :easter_offset,
    offset_days: -47  # 47 days before Easter (Shrove Tuesday)
  },
  {
    name: 'Sexta-feira Santa',
    calculation_type: :easter_offset,
    offset_days: -2  # Good Friday (2 days before Easter)
  },
  {
    name: 'Corpus Christi',
    calculation_type: :easter_offset,
    offset_days: 60  # 60 days after Easter (second Thursday after Pentecost)
  }
]

holidays.each do |holiday_data|
  holiday = Holiday.find_or_initialize_by(
    boundary: brazil,
    name: holiday_data[:name]
  )

  holiday.assign_attributes(
    month: holiday_data[:month],
    day: holiday_data[:day],
    calculation_type: holiday_data[:calculation_type],
    offset_days: holiday_data[:offset_days]
  )

  if holiday.save
    puts "✓ #{holiday.name} - #{holiday.calculation_description}"
  else
    puts "✗ Error creating #{holiday_data[:name]}: #{holiday.errors.full_messages.join(', ')}"
  end
end

puts "\nBrazil holidays created successfully!"
puts "\n2027 Holiday Dates:"
Holiday.where(boundary: brazil).each do |holiday|
  date = holiday.date_for_year(2027)
  puts "  #{date.strftime('%B %d, %Y (%A)')}: #{holiday.name}"
end

# db/seeds/brazil_state_holidays.rb
# Brazil State Holidays
#
# Each Brazilian state has one official state holiday (Federal Law 9.093/1995)
# These celebrate historical events, founding dates, or important local figures
#
# Sources:
# - https://en.wikipedia.org/wiki/Public_holidays_in_Brazil
# - https://grokipedia.com/page/Public_holidays_in_Brazil
# - Various state government sources

puts 'Creating Brazil state holidays...'

# State holiday data
# Format: [state_name, holiday_name, month, day]
state_holidays = [
  # North Region
  ['Acre', 'Revolução Acreana', 6, 15],
  ['Acre', 'Dia da Amazônia', 9, 5],
  ['Acre', 'Tratado de Petrópolis', 11, 17],
  ['Amapá', 'Dia de São José', 3, 19],
  ['Amapá', 'Criação do Território do Amapá', 9, 13],
  ['Amazonas', 'Elevação do Amazonas à Categoria de Província', 9, 5],
  ['Pará', 'Adesão do Pará à Independência', 8, 15],
  ['Rondônia', 'Criação do Estado de Rondônia', 1, 4],
  ['Roraima', 'Criação do Estado de Roraima', 10, 5],
  ['Tocantins', 'Autonomia do Tocantins', 3, 18],
  ['Tocantins', 'Nossa Senhora da Natividade', 9, 8],
  ['Tocantins', 'Criação do Estado do Tocantins', 10, 5],

  # Northeast Region
  ['Alagoas', 'Emancipação Política de Alagoas', 9, 16],
  ['Alagoas', 'Dia de São João', 6, 24],
  ['Alagoas', 'Dia de São Pedro e São Paulo', 6, 29],
  ['Alagoas', 'Dia do Evangêlico', 11, 30],
  ['Bahia', 'Independência da Bahia', 7, 2],
  ['Ceará', 'Dia de São José', 3, 19],
  ['Maranhão', 'Adesão do Maranhão à Independência', 7, 28],
  ['Paraíba', 'Fundação da Paraíba', 8, 5],
  ['Pernambuco', 'Revolução Pernambucana', 3, 6],
  ['Pernambuco', 'Dia de São João', 6, 24],
  ['Piauí', 'Dia do Piauí', 10, 19],
  ['Rio Grande do Norte', 'Mártires de Cunhaú e Uruaçu', 10, 3],
  ['Sergipe', 'Emancipação Política de Sergipe', 7, 8],

  # Central-West Region
  ['Distrito Federal', 'Dia do Evangélico', 11, 30],
  ['Goiás', 'Dia do Servidor Público', 10, 28],
  ['Mato Grosso', 'Dia do Estado de Mato Grosso', 12, 15],
  ['Mato Grosso do Sul', 'Criação do Estado', 10, 11],

  # Southeast Region
  ['Espírito Santo', 'Colonização do Solo Espírito-Santense', 5, 23],
  ['Rio de Janeiro', 'Dia de São Jorge', 4, 23],
  ['São Paulo', 'Revolução Constitucionalista', 7, 9],

  # South Region
  ['Paraná', 'Emancipação do Paraná', 12, 19],
  ['Rio Grande do Sul', 'Revolução Farroupilha', 9, 20],
  ['Santa Catarina', 'Criação da Capitania', 8, 11],
  ['Santa Catarina', 'Dia de Santa Catarina de Alexandria', 11, 25]
]

# Create holidays for each state
state_holidays.each do |state_name, holiday_name, month, day|
  # Find the state boundary
  boundary = Boundary.find_by(level: 4, name: state_name)

  unless boundary
    puts "✗ State boundary not found for: #{state_name}"
    next
  end

  holiday = Holiday.find_or_initialize_by(
    boundary: boundary,
    name: holiday_name
  )

  holiday.assign_attributes(
    month: month,
    day: day,
    calculation_type: :fixed,
    offset_days: 0
  )

  if holiday.save
    date = holiday.date_for_year(2027)
    puts "✓ #{state_name}: #{holiday.name} - #{date.strftime('%B %d, %Y (%A)')}"
  else
    puts "✗ Error creating #{holiday_name} for #{state_name}: #{holiday.errors.full_messages.join(', ')}"
  end
end

puts "\nBrazil state holidays created successfully!"
