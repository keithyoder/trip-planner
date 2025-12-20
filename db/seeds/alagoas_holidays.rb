# db/seeds/alagoas_municipal_holidays.rb
# Alagoas Municipal Holidays (Hardcoded)
#
# This seed file creates permanent municipal holidays for all municipalities
# in Alagoas that do not overlap with national or state holidays.
#
# Data source: Feriados Municipais - AL (2025)
# Excludes: National holidays and Alagoas state holiday (Sep 16)

puts 'Creating Alagoas municipal holidays...'

# Municipal holidays data
# Format: [municipality_name, month, day, holiday_name]
MUNICIPAL_HOLIDAYS = [
  # January
  ['Maravilha', 1, 2, 'Feriado Municipal'],
  ['Marechal Deodoro', 1, 6, 'Dia de Reis'],
  ['São José da Laje', 1, 6, 'Dia de Reis'],
  ['Maribondo', 1, 15, 'Feriado Municipal'],
  ['Dois Riachos', 1, 20, 'Dia de São Sebastião'],
  ['Joaquim Gomes', 1, 20, 'Dia de São Sebastião'],
  ['Limoeiro de Anadia', 1, 20, 'Dia de São Sebastião'],
  ['Passo de Camaragibe', 1, 20, 'Dia de São Sebastião'],
  ['Porto Calvo', 1, 20, 'Dia de São Sebastião'],
  ['Poço das Trincheiras', 1, 20, 'Dia de São Sebastião'],
  ['São Sebastião', 1, 20, 'Dia de São Sebastião'],

  # February
  ['Atalaia', 2, 1, 'Feriado Municipal'],
  ['Anadia', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Arapiraca', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Atalaia', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Dois Riachos', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Olivença', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Paulo Jacinto', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Pilar', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Piranhas', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['São Luís do Quitunde', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['União dos Palmares', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Viçosa', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Delmiro Gouveia', 2, 14, 'Feriado Municipal'],

  # March
  ['Pão de Açúcar', 3, 3, 'Feriado Municipal'],
  ['Girau do Ponciano', 3, 8, 'Feriado Municipal'],
  ['Pilar', 3, 16, 'Feriado Municipal'],
  ['Quebrangulo', 3, 16, 'Feriado Municipal'],
  ['Mata Grande', 3, 18, 'Feriado Municipal'],
  ['Anadia', 3, 19, 'Dia de São José'],
  ['Canapi', 3, 19, 'Dia de São José'],
  ['Marechal Deodoro', 3, 19, 'Dia de São José'],
  ['Porto Calvo', 3, 19, 'Dia de São José'],
  ['São José da Laje', 3, 19, 'Dia de São José'],
  ['São José da Tapera', 3, 19, 'Dia de São José'],

  # April
  ['Pariconha', 4, 7, 'Feriado Municipal'],
  ['Penedo', 4, 12, 'Feriado Municipal'],
  ['Porto Calvo', 4, 12, 'Feriado Municipal'],
  ['Craíbas', 4, 23, 'Dia de São Jorge'],
  ['Maragogi', 4, 24, 'Feriado Municipal'],
  ['Matriz de Camaragibe', 4, 24, 'Feriado Municipal'],
  ['Santana do Ipanema', 4, 24, 'Feriado Municipal'],
  ['Água Branca', 4, 24, 'Feriado Municipal'],
  ['Feira Grande', 4, 25, 'Feriado Municipal'],

  # May
  ['Passo de Camaragibe', 5, 3, 'Dia de Santa Cruz'],
  ['Taquarana', 5, 3, 'Dia de Santa Cruz'],
  ['Coruripe', 5, 16, 'Dia de São Simão'],
  ['Igreja Nova', 5, 16, 'Dia de São Simão'],
  ['São Luís do Quitunde', 5, 16, 'Dia de São Simão'],
  ['Traipu', 5, 16, 'Dia de São Simão'],
  ['Boca da Mata', 5, 22, 'Feriado Municipal'],
  ['Matriz de Camaragibe', 5, 24, 'Feriado Municipal'],
  ['Campo Grande', 5, 31, 'Feriado Municipal'],
  ['Limoeiro de Anadia', 5, 31, 'Feriado Municipal'],
  ['Piaçabuçu', 5, 31, 'Feriado Municipal'],
  ['São Sebastião', 5, 31, 'Feriado Municipal'],

  # June
  ['Campo Grande', 6, 1, 'Feriado Municipal'],
  ['Major Izidoro', 6, 1, 'Feriado Municipal'],
  ['Piranhas', 6, 3, 'Feriado Municipal'],
  ['Major Izidoro', 6, 13, 'Dia de Santo Antônio'],
  ['Maragogi', 6, 13, 'Dia de Santo Antônio'],
  ["Olho d'Água das Flores", 6, 13, 'Dia de Santo Antônio'],
  ['Ouro Branco', 6, 13, 'Dia de Santo Antônio'],
  ['Passo de Camaragibe', 6, 14, 'Feriado Municipal'],
  ['Ouro Branco', 6, 21, 'Feriado Municipal'],

  # July
  ['Pilar', 7, 7, 'Feriado Municipal'],
  ['Porto Real do Colégio', 7, 7, 'Feriado Municipal'],
  ['Dois Riachos', 7, 8, 'Feriado Municipal'],
  ['Junqueiro', 7, 9, 'Feriado Municipal'],
  ['Rio Largo', 7, 13, 'Feriado Municipal'],
  ['Girau do Ponciano', 7, 15, 'Feriado Municipal'],
  ['Colônia Leopoldina', 7, 16, 'Dia de Nossa Senhora do Carmo'],
  ['Olivença', 7, 16, 'Dia de Nossa Senhora do Carmo'],
  ['Anadia', 7, 18, 'Feriado Municipal'],
  ['Anadia', 7, 20, "Dia de Sant'Ana"],
  ['Atalaia', 7, 20, "Dia de Sant'Ana"],
  ['Boca da Mata', 7, 20, "Dia de Sant'Ana"],
  ['Dois Riachos', 7, 20, "Dia de Sant'Ana"],
  ['Lagoa da Canoa', 7, 20, "Dia de Sant'Ana"],
  ['Poço das Trincheiras', 7, 20, "Dia de Sant'Ana"],
  ['Porto Calvo', 7, 22, 'Feriado Municipal'],
  ['União dos Palmares', 7, 22, 'Feriado Municipal'],
  ['Maribondo', 7, 25, 'Feriado Municipal'],
  ['Barra de São Miguel', 7, 26, 'Feriado Municipal'],
  ['Santana do Ipanema', 7, 26, 'Feriado Municipal'],
  ['São José da Laje', 7, 28, 'Feriado Municipal'],

  # August
  ['Barra de São Miguel', 8, 2, 'Feriado Municipal'],
  ['Marechal Deodoro', 8, 5, 'Feriado Municipal'],
  ['Lagoa da Canoa', 8, 14, 'Feriado Municipal'],
  ['Porto Real do Colégio', 8, 16, 'Dia de São Roque'],
  ['Palmeira dos Índios', 8, 20, 'Feriado Municipal'],
  ['Canapi', 8, 22, 'Feriado Municipal'],
  ['Inhapi', 8, 22, 'Feriado Municipal'],
  ['Ouro Branco', 8, 22, 'Feriado Municipal'],
  ['Maribondo', 8, 24, 'Feriado Municipal'],
  ['Taquarana', 8, 24, 'Feriado Municipal'],
  ['Joaquim Gomes', 8, 25, 'Feriado Municipal'],
  ['Maceió', 8, 27, 'Dia de Nossa Senhora dos Prazeres'],
  ['Lagoa da Canoa', 8, 28, 'Feriado Municipal'],

  # September
  ['Batalha', 9, 8, 'Dia de Nossa Senhora da Penha'],
  ['Cacimbinhas', 9, 8, 'Dia de Nossa Senhora da Penha'],
  ['São Sebastião', 9, 8, 'Dia de Nossa Senhora da Penha'],
  ['São José da Tapera', 9, 15, 'Feriado Municipal'],
  ['Coité do Nóia', 9, 21, 'Feriado Municipal'],
  ['Quebrangulo', 9, 27, 'Feriado Municipal'],
  ['São Miguel dos Campos', 9, 29, 'Dia de São Miguel Arcanjo'],

  # October
  ['Igaci', 10, 4, 'Dia de São Francisco de Assis'],
  ['Piranhas', 10, 4, 'Dia de São Francisco de Assis'],
  ['Estrela de Alagoas', 10, 5, 'Feriado Municipal'],
  ['Delmiro Gouveia', 10, 7, 'Feriado Municipal'],
  ['Inhapi', 10, 7, 'Feriado Municipal'],
  ['Penedo', 10, 7, 'Feriado Municipal'],
  ['Delmiro Gouveia', 10, 10, 'Feriado Municipal'],
  ['União dos Palmares', 10, 13, 'Feriado Municipal'],
  ['Viçosa', 10, 13, 'Feriado Municipal'],
  ['Quebrangulo', 10, 27, 'Feriado Municipal'],
  ['Ouro Branco', 10, 28, 'Feriado Municipal'],
  ['Arapiraca', 10, 30, 'Feriado Municipal'],

  # December
  ['Novo Lino', 12, 1, 'Feriado Municipal'],
  ['Paulo Jacinto', 12, 2, 'Feriado Municipal'],
  ['Maravilha', 12, 7, 'Feriado Municipal'],
  ['Campo Grande', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Capela', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Coruripe', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Craíbas', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Feira Grande', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Girau do Ponciano', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Igreja Nova', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Lagoa da Canoa', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Limoeiro de Anadia', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Maceió', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Maravilha', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Marechal Deodoro', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Maribondo', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Ouro Branco', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Palmeira dos Índios', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Penedo', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Piaçabuçu', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Pilar', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Porto Real do Colégio', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Poço das Trincheiras', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Pão de Açúcar', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Rio Largo', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Santana do Ipanema', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['União dos Palmares', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Água Branca', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Teotônio Vilela', 12, 12, 'Feriado Municipal'],
  ['Anadia', 12, 13, 'Dia de Santa Luzia'],
  ['Campo Grande', 12, 13, 'Dia de Santa Luzia'],
  ['Matriz de Camaragibe', 12, 13, 'Dia de Santa Luzia'],
  ['São Miguel dos Campos', 12, 18, 'Feriado Municipal'],
  ['Traipu', 12, 18, 'Feriado Municipal'],
  ['Batalha', 12, 22, 'Feriado Municipal']

].freeze

# Track statistics
created_count = 0
updated_count = 0
error_count = 0
boundary_not_found = []

# Create holidays
state = Boundary.find_by(level: 4, name: 'Alagoas')

MUNICIPAL_HOLIDAYS.each do |municipality_name, month, day, holiday_name| # rubocop:disable Metrics/BlockLength
  # Find the municipality boundary
  boundary = state.descendants_at_level(8).find_by(name: municipality_name)

  unless boundary
    boundary_not_found << municipality_name unless boundary_not_found.include?(municipality_name)
    error_count += 1
    next
  end

  # Create or update the holiday
  holiday = Holiday.find_or_initialize_by(
    boundary: boundary,
    month: month,
    day: day
  )

  holiday.assign_attributes(
    name: holiday_name,
    calculation_type: :fixed,
    offset_days: 0
  )

  if holiday.save
    if holiday.previously_new_record?
      created_count += 1
      date = holiday.date_for_year(2025)
      puts "✓ #{municipality_name}: #{holiday.name} - #{date.strftime('%b %d')}"
    else
      updated_count += 1
    end
  else
    error_count += 1
    puts "✗ Error creating holiday for #{municipality_name} (#{month}/#{day}): #{holiday.errors.full_messages.join(', ')}"
  end
end

puts "\n#{'=' * 80}"
puts 'Alagoas Municipal Holidays Summary'
puts '=' * 80
puts "✓ Created: #{created_count} holidays"
puts "↻ Updated: #{updated_count} holidays"
puts "⊘ Errors: #{error_count}"

if boundary_not_found.any?
  puts "\n⚠ Boundaries not found for #{boundary_not_found.uniq.count} municipalities:"
  boundary_not_found.uniq.sort.each do |name|
    puts "  - #{name}"
  end
  puts "\nThese municipalities need to be imported or their names normalized."
end

# Show summary statistics
puts "\nHoliday Distribution:"
holiday_counts = Holiday
                 .joins(:boundary)
                 .where('boundaries.level = 8')
                 .where(boundaries: { name: MUNICIPAL_HOLIDAYS.map(&:first).uniq })
                 .group(:name)
                 .count
                 .sort_by { |_, count| -count }

holiday_counts.each do |name, count|
  puts "  #{name}: #{count} municipalities"
end

puts "\n✓ Alagoas municipal holidays seed completed!"
