# db/seeds/pernambuco_municipal_holidays_hardcoded.rb
# Pernambuco Municipal Holidays (Hardcoded)
#
# This seed file creates permanent municipal holidays for all municipalities
# in Pernambuco that do not overlap with national or state holidays.
#
# Data source: Feriados Municipais - PE (2025)
# Excludes: National holidays and Pernambuco state holidays (Mar 6, Jun 24)

puts 'Creating Pernambuco municipal holidays...'

# Municipal holidays data
# Format: [municipality_name, month, day, holiday_name]
MUNICIPAL_HOLIDAYS = [
  # January
  ['Inajá', 1, 2, 'Feriado Municipal'],
  ['Brejão', 1, 6, 'Dia de Reis'],
  ['Carpina', 1, 6, 'Dia de Reis'],
  ['Catende', 1, 6, 'Dia de Reis'],
  ['Cupira', 1, 6, 'Dia de Reis'],
  ['Macaparana', 1, 6, 'Dia de Reis'],
  ['Pedra', 1, 6, 'Dia de Reis'],
  ['São Bento do Una', 1, 6, 'Dia de Reis'],
  ['São Joaquim do Monte', 1, 6, 'Dia de Reis'],
  ['São José do Egito', 1, 6, 'Dia de Reis'],
  ['Altinho', 1, 7, 'Feriado Municipal'],
  ['São Bento do Una', 1, 7, 'Feriado Municipal'],
  ['Itapissuma', 1, 10, 'Feriado Municipal'],
  ['Exu', 1, 14, 'Feriado Municipal'],
  ['Jaboatão dos Guararapes', 1, 15, 'Feriado Municipal'],
  ['Sirinhaém', 1, 15, 'Feriado Municipal'],
  ['Taquaritinga do Norte', 1, 15, 'Feriado Municipal'],
  ['Vitória de Santo Antão', 1, 17, 'Feriado Municipal'],
  ['Pombos', 1, 18, 'Feriado Municipal'],
  ['Águas Belas', 1, 20, 'Dia de São Sebastião'],
  ['Aliança', 1, 20, 'Dia de São Sebastião'],
  ['Belo Jardim', 1, 20, 'Dia de São Sebastião'],
  ['Bom Conselho', 1, 20, 'Dia de São Sebastião'],
  ['Bonito', 1, 20, 'Dia de São Sebastião'],
  ['Chã Grande', 1, 20, 'Dia de São Sebastião'],
  ['Iguaracy', 1, 20, 'Dia de São Sebastião'],
  ['Jataúba', 1, 20, 'Dia de São Sebastião'],
  ['Lagoa de Itaenga', 1, 20, 'Dia de São Sebastião'],
  ['Lagoa dos Gatos', 1, 20, 'Dia de São Sebastião'],
  ['Machados', 1, 20, 'Dia de São Sebastião'],
  ['Moreno', 1, 20, 'Dia de São Sebastião'],
  ['Orocó', 1, 20, 'Dia de São Sebastião'],
  ['Ouricuri', 1, 20, 'Dia de São Sebastião'],
  ['Riacho das Almas', 1, 20, 'Dia de São Sebastião'],
  ['Surubim', 1, 20, 'Dia de São Sebastião'],
  ['Terra Nova', 1, 20, 'Dia de São Sebastião'],
  ['Iati', 1, 25, 'Feriado Municipal'],
  ['Tabira', 1, 27, 'Feriado Municipal'],
  ['Mirandiba', 1, 28, 'Feriado Municipal'],

  # February
  ['Agrestina', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Barreiros', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Belém de Maria', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Bom Jardim', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Canhotinho', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Ilha de Itamaracá', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Itambé', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['São Vicente Férrer', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Tacaratu', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Toritama', 2, 2, 'Dia de Nossa Senhora dos Navegantes'],
  ['Bom Jardim', 2, 3, 'Feriado Municipal'],
  ['Lagoa do Carro', 2, 3, 'Feriado Municipal'],
  ['Ouricuri', 2, 3, 'Feriado Municipal'],
  ['Garanhuns', 2, 4, 'Feriado Municipal'],
  ['Pesqueira', 2, 5, 'Santa Águeda'],
  ['Panelas', 2, 6, 'Feriado Municipal'],
  ['Rio Formoso', 2, 7, 'Feriado Municipal'],
  ['Cedro', 2, 11, 'Feriado Municipal'],

  # March
  ['Brejão', 3, 1, 'Feriado Municipal'],
  ['Terra Nova', 3, 1, 'Feriado Municipal'],
  ['Ipubi', 3, 2, 'Feriado Municipal'],
  ['Jataúba', 3, 2, 'Feriado Municipal'],
  ['Cedro', 3, 8, 'Feriado Municipal'],
  ['São José do Egito', 3, 9, 'Feriado Municipal'],
  ['Mirandiba', 3, 11, 'Feriado Municipal'],
  ['Olinda', 3, 12, 'Feriado Municipal'],
  ['Chã Grande', 3, 15, 'Feriado Municipal'],
  ['Gravatá', 3, 15, 'Feriado Municipal'],
  ['Toritama', 3, 17, 'Feriado Municipal'],
  ['Abreu e Lima', 3, 19, 'Dia de São José'],
  ['Água Preta', 3, 19, 'Dia de São José'],
  ['Amaraji', 3, 19, 'Dia de São José'],
  ['Bezerros', 3, 19, 'Dia de São José'],
  ['Bodocó', 3, 19, 'Dia de São José'],
  ['Brejo da Madre de Deus', 3, 19, 'Dia de São José'],
  ['Capoeiras', 3, 19, 'Dia de São José'],
  ['Carpina', 3, 19, 'Dia de São José'],
  ['Cumaru', 3, 19, 'Dia de São José'],
  ['Custódia', 3, 19, 'Dia de São José'],
  ['Dormentes', 3, 19, 'Dia de São José'],
  ['Feira Nova', 3, 19, 'Dia de São José'],
  ['Frei Miguelinho', 3, 19, 'Dia de São José'],
  ['Iguaracy', 3, 19, 'Dia de São José'],
  ['Inajá', 3, 19, 'Dia de São José'],
  ['Passira', 3, 19, 'Dia de São José'],
  ['Rio Formoso', 3, 19, 'Dia de São José'],
  ['São José da Coroa Grande', 3, 19, 'Dia de São José'],
  ['São José do Belmonte', 3, 19, 'Dia de São José'],
  ['São José do Egito', 3, 19, 'Dia de São José'],
  ['Surubim', 3, 19, 'Dia de São José'],
  ['Taquaritinga do Norte', 3, 19, 'Dia de São José'],
  ['Tupanatinga', 3, 19, 'Dia de São José'],
  ['Venturosa', 3, 19, 'Dia de São José'],
  ['Vertentes', 3, 19, 'Dia de São José'],
  ['Venturosa', 3, 20, 'Feriado Municipal'],
  ['Ipojuca', 3, 30, 'Feriado Municipal'],
  ['Floresta', 3, 31, 'Feriado Municipal'],

  # April
  ['São Vicente Férrer', 4, 5, 'Dia de São Vicente Ferrer'],
  ['Timbaúba', 4, 8, 'Feriado Municipal'],
  ['Gameleira', 4, 10, 'Feriado Municipal'],
  ['São José da Coroa Grande', 4, 11, 'Feriado Municipal'],
  ['Tuparetama', 4, 11, 'Feriado Municipal'],
  ['Águas Belas', 4, 19, 'Feriado Municipal'],
  ['Pesqueira', 4, 20, 'Feriado Municipal'],
  ['Bom Conselho', 4, 26, 'Feriado Municipal'],
  ['Itaíba', 4, 28, 'Feriado Municipal'],
  ['Salgueiro', 4, 30, 'Feriado Municipal'],
  ['São Bento do Una', 4, 30, 'Feriado Municipal'],

  # May
  ['Panelas', 5, 2, 'Feriado Municipal'],
  ['Belém de Maria', 5, 3, 'Feriado Municipal'],
  ['Tacaratu', 5, 3, 'Feriado Municipal'],
  ['Jaboatão dos Guararapes', 5, 4, 'Feriado Municipal'],
  ['Sairé', 5, 6, 'Feriado Municipal'],
  ['Serra Talhada', 5, 6, 'Feriado Municipal'],
  ['Belém de São Francisco', 5, 7, 'Feriado Municipal'],
  ['Taquaritinga do Norte', 5, 10, 'Feriado Municipal'],
  ['Camaragibe', 5, 13, 'Dia de Nossa Senhora de Fátima'],
  ['Parnamirim', 5, 13, 'Dia de Nossa Senhora de Fátima'],
  ['Pedra', 5, 13, 'Dia de Nossa Senhora de Fátima'],
  ['Tacaratu', 5, 13, 'Dia de Nossa Senhora de Fátima'],
  ['Abreu e Lima', 5, 14, 'Feriado Municipal'],
  ['Ouricuri', 5, 14, 'Feriado Municipal'],
  ['Itapissuma', 5, 15, 'Feriado Municipal'],
  ['Nazaré da Mata', 5, 17, 'Feriado Municipal'],
  ['Bezerros', 5, 18, 'Feriado Municipal'],
  ['Buíque', 5, 18, 'Feriado Municipal'],
  ['Camocim de São Félix', 5, 18, 'Feriado Municipal'],
  ['Caruaru', 5, 18, 'Feriado Municipal'],
  ['Panelas', 5, 18, 'Feriado Municipal'],
  ['Lajedo', 5, 19, 'Feriado Municipal'],
  ['Moreilândia', 5, 19, 'Feriado Municipal'],
  ['Quipapá', 5, 19, 'Feriado Municipal'],
  ['Bonito', 5, 20, 'Feriado Municipal'],
  ['Escada', 5, 24, 'Feriado Municipal'],
  ['Lagoa Grande', 5, 24, 'Feriado Municipal'],
  ['Sertânia', 5, 24, 'Feriado Municipal'],
  ['Brejo da Madre de Deus', 5, 26, 'Feriado Municipal'],
  ['Tabira', 5, 27, 'Feriado Municipal'],
  ['Afrânio', 5, 31, 'Feriado Municipal'],
  ['Bodocó', 5, 31, 'Feriado Municipal'],

  # June
  ['Cedro', 6, 2, 'Feriado Municipal'],
  ['Pedra', 6, 4, 'Feriado Municipal'],
  ['Santa Maria da Boa Vista', 6, 7, 'Feriado Municipal'],
  ['Palmares', 6, 9, 'Feriado Municipal'],
  ['Camaragibe', 6, 10, 'Feriado Municipal'],
  ['Rio Formoso', 6, 11, 'Feriado Municipal'],
  ['Sirinhaém', 6, 12, 'Feriado Municipal'],
  ['Agrestina', 6, 13, 'Dia de Santo Antônio'],
  ['Cabo de Santo Agostinho', 6, 13, 'Dia de Santo Antônio'],
  ['Cachoeirinha', 6, 13, 'Dia de Santo Antônio'],
  ['Carnaíba', 6, 13, 'Dia de Santo Antônio'],
  ['Carpina', 6, 13, 'Dia de Santo Antônio'],
  ['Garanhuns', 6, 13, 'Dia de Santo Antônio'],
  ['Ibimirim', 6, 13, 'Dia de Santo Antônio'],
  ['Inajá', 6, 13, 'Dia de Santo Antônio'],
  ['Lajedo', 6, 13, 'Dia de Santo Antônio'],
  ['Salgueiro', 6, 13, 'Dia de Santo Antônio'],
  ['Triunfo', 6, 13, 'Dia de Santo Antônio'],
  ['Lagoa Grande', 6, 16, 'Feriado Municipal'],
  ['Brejo da Madre de Deus', 6, 20, 'Feriado Municipal'],
  ['Floresta', 6, 20, 'Feriado Municipal'],
  ['São José do Belmonte', 6, 26, 'Feriado Municipal'],
  ['Altinho', 6, 28, 'Feriado Municipal'],
  ['Amaraji', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Bom Jardim', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Bonito', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Cachoeirinha', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Caruaru', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Fernando de Noronha', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Itapetim', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Lagoa de Itaenga', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Machados', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Pedra', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Sanharó', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Santa Terezinha', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['São José da Coroa Grande', 6, 29, 'Dia de São Pedro e São Paulo'],
  ['Tamandaré', 6, 29, 'Dia de São Pedro e São Paulo'],

  # July
  ['Afogados da Ingazeira', 7, 1, 'Feriado Municipal'],
  ['Parnamirim', 7, 1, 'Feriado Municipal'],
  ['Petrolândia', 7, 1, 'Feriado Municipal'],
  ['Cabo de Santo Agostinho', 7, 9, 'Feriado Municipal'],
  ['Glória do Goitá', 7, 9, 'Feriado Municipal'],
  ['Recife', 7, 16, 'Feriado Municipal'],
  ['Tupanatinga', 7, 16, 'Feriado Municipal'],
  ['Bodocó', 7, 18, 'Feriado Municipal'],
  ['Barreiros', 7, 19, 'Feriado Municipal'],
  ['Tamandaré', 7, 19, 'Feriado Municipal'],
  ['Afogados da Ingazeira', 7, 22, 'Feriado Municipal'],
  ['Amaraji', 7, 23, 'Feriado Municipal'],
  ['Bom Jardim', 7, 26, 'Feriado Municipal'],
  ['Gravatá', 7, 26, 'Feriado Municipal'],
  ['Parnamirim', 7, 26, 'Feriado Municipal'],
  ['Ribeirão', 7, 26, 'Feriado Municipal'],
  ['São Joaquim do Monte', 7, 26, 'Feriado Municipal'],
  ['Vicência', 7, 26, 'Feriado Municipal'],
  ['Limoeiro', 7, 27, 'Feriado Municipal'],
  ['Paudalho', 7, 27, 'Feriado Municipal'],
  ['Tamandaré', 7, 31, 'Feriado Municipal'],

  # August
  ['Exu', 8, 2, 'Feriado Municipal'],
  ['Água Preta', 8, 3, 'Feriado Municipal'],
  ['Bom Conselho', 8, 3, 'Feriado Municipal'],
  ['Itambé', 8, 3, 'Feriado Municipal'],
  ['Vitória de Santo Antão', 8, 3, 'Feriado Municipal'],
  ['Carnaíba', 8, 4, 'Feriado Municipal'],
  ['Olinda', 8, 6, 'Feriado Municipal'],
  ['Caetés', 8, 7, 'Feriado Municipal'],
  ['São Caetano', 8, 7, 'Feriado Municipal'],
  ['Fernando de Noronha', 8, 10, 'Feriado Municipal'],
  ['São Lourenço da Mata', 8, 10, 'Feriado Municipal'],
  ['Tupanatinga', 8, 11, 'Feriado Municipal'],
  ['Iati', 8, 14, 'Feriado Municipal'],
  ['Glória do Goitá', 8, 15, 'Dia de Nossa Senhora da Assunção'],
  ['Iguaracy', 8, 15, 'Dia de Nossa Senhora da Assunção'],
  ['Ipubi', 8, 15, 'Dia de Nossa Senhora da Assunção'],
  ['Petrolina', 8, 15, 'Dia de Nossa Senhora da Assunção'],
  ['Pombos', 8, 15, 'Dia de Nossa Senhora da Assunção'],
  ['Tabira', 8, 15, 'Dia de Nossa Senhora da Assunção'],
  ['Vertentes', 8, 15, 'Dia de Nossa Senhora da Assunção'],
  ['Sirinhaém', 8, 16, 'Feriado Municipal'],
  ['Pedra', 8, 17, 'Feriado Municipal'],
  ['Lagoa do Carro', 8, 22, 'Feriado Municipal'],
  ['Correntes', 8, 27, 'Feriado Municipal'],
  ['Cupira', 8, 29, 'Feriado Municipal'],
  ['Fernando de Noronha', 8, 29, 'Feriado Municipal'],

  # September
  ['Paulista', 9, 4, 'Feriado Municipal'],
  ['Exu', 9, 8, 'Dia de Nossa Senhora das Dores'],
  ['Serra Talhada', 9, 8, 'Dia de Nossa Senhora das Dores'],
  ['Agrestina', 9, 11, 'Feriado Municipal'],
  ['Aliança', 9, 11, 'Feriado Municipal'],
  ['Araripina', 9, 11, 'Feriado Municipal'],
  ['Arcoverde', 9, 11, 'Feriado Municipal'],
  ['Belo Jardim', 9, 11, 'Feriado Municipal'],
  ['Cabrobó', 9, 11, 'Feriado Municipal'],
  ['Carpina', 9, 11, 'Feriado Municipal'],
  ['Catende', 9, 11, 'Feriado Municipal'],
  ['Custódia', 9, 11, 'Feriado Municipal'],
  ['Flores', 9, 11, 'Feriado Municipal'],
  ['Jurema', 9, 11, 'Feriado Municipal'],
  ['Lagoa dos Gatos', 9, 11, 'Feriado Municipal'],
  ['Moreno', 9, 11, 'Feriado Municipal'],
  ['Orobó', 9, 11, 'Feriado Municipal'],
  ['Ribeirão', 9, 11, 'Feriado Municipal'],
  ['São Caetano', 9, 11, 'Feriado Municipal'],
  ['São Joaquim do Monte', 9, 11, 'Feriado Municipal'],
  ['Serrita', 9, 11, 'Feriado Municipal'],
  ['Surubim', 9, 11, 'Feriado Municipal'],
  ['Vicência', 9, 11, 'Feriado Municipal'],
  ['Caetés', 9, 13, 'Feriado Municipal'],
  ['Brejão', 9, 14, 'Feriado Municipal'],
  ['Aliança', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Belém de Maria', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Caruaru', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Condado', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Poção', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['São José do Belmonte', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Terra Nova', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Timbaúba', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Triunfo', 9, 15, 'Dia de Nossa Senhora das Dores'],
  ['Moreilândia', 9, 17, 'Feriado Municipal'],
  ['Petrolina', 9, 21, 'Feriado Municipal'],
  ['Arcoverde', 9, 23, 'Dia de Nossa Senhora do Livramento'],
  ['Igarassu', 9, 27, 'Feriado Municipal'],
  ['Saloá', 9, 27, 'Feriado Municipal'],
  ['Jatobá', 9, 28, 'Feriado Municipal'],
  ['Tamandaré', 9, 28, 'Feriado Municipal'],
  ['Barreiros', 9, 29, 'Dia de São Miguel Arcanjo'],
  ['Ipojuca', 9, 29, 'Dia de São Miguel Arcanjo'],
  ['Sairé', 9, 29, 'Dia de São Miguel Arcanjo'],
  ['Santa Cruz do Capibaribe', 9, 29, 'Dia de São Miguel Arcanjo'],
  ['Trindade', 9, 29, 'Dia de São Miguel Arcanjo'],

  # October
  ['Cumaru', 10, 1, 'Feriado Municipal'],
  ['Dormentes', 10, 1, 'Feriado Municipal'],
  ['Lagoa do Carro', 10, 1, 'Feriado Municipal'],
  ['Santa Terezinha', 10, 1, 'Feriado Municipal'],
  ['Canhotinho', 10, 2, 'Feriado Municipal'],
  ['Bodocó', 10, 4, 'Feriado Municipal'],
  ['Petrolândia', 10, 4, 'Feriado Municipal'],
  ['Santa Cruz do Capibaribe', 10, 5, 'Feriado Municipal'],
  ['Parnamirim', 10, 8, 'Feriado Municipal'],
  ['Cedro', 10, 9, 'Feriado Municipal'],
  ['João Alfredo', 10, 10, 'Feriado Municipal'],
  ['Sanharó', 10, 20, 'Feriado Municipal'],
  ['Capoeiras', 10, 28, 'Feriado Municipal'],
  ['Abreu e Lima', 10, 31, 'Feriado Municipal'],
  ['Amaraji', 10, 31, 'Feriado Municipal'],
  ['Cabo de Santo Agostinho', 10, 31, 'Feriado Municipal'],
  ['Ipubi', 10, 31, 'Feriado Municipal'],
  ['Tuparetama', 10, 31, 'Feriado Municipal'],

  # November
  ['Rio Formoso', 11, 24, 'Feriado Municipal'],
  ['São João', 11, 25, 'Feriado Municipal'],

  # December
  ['Águas Belas', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Alagoinha', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Araripina', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Belém de São Francisco', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Belo Jardim', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Bezerros', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Bonito', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Brejão', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Cabrobó', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Camaragibe', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Canhotinho', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Correntes', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Escada', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Flores', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Glória do Goitá', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Igarassu', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Itaíba', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Ilha de Itamaracá', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Itambé', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Itapetim', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Itapissuma', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['João Alfredo', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Jurema', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Lagoa dos Gatos', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Machados', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Moreno', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Nazaré da Mata', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Orobó', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Palmares', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Palmeirina', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Passira', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Pedra', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Pesqueira', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Quipapá', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Recife', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Riacho das Almas', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Santa Maria da Boa Vista', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['São Vicente Férrer', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Serrita', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Sertânia', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Sirinhaém', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Taquaritinga do Norte', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Timbaúba', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Toritama', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Vertentes', 12, 8, 'Dia de Nossa Senhora da Conceição'],
  ['Orobó', 12, 9, 'Feriado Municipal'],
  ['Pombos', 12, 11, 'Feriado Municipal'],
  ['Exu', 12, 13, 'Feriado Municipal'],
  ['Cachoeirinha', 12, 17, 'Feriado Municipal'],
  ['Altinho', 12, 18, 'Feriado Municipal'],
  ['Buenos Aires', 12, 20, 'Feriado Municipal'],
  ['Cedro', 12, 20, 'Feriado Municipal'],
  ['Chã Grande', 12, 20, 'Feriado Municipal'],
  ['Cumaru', 12, 20, 'Feriado Municipal'],
  ['Feira Nova', 12, 20, 'Feriado Municipal'],
  ['Frei Miguelinho', 12, 20, 'Feriado Municipal'],
  ['Ibimirim', 12, 20, 'Feriado Municipal'],
  ['Iguaracy', 12, 20, 'Feriado Municipal'],
  ['Lagoa de Itaenga', 12, 20, 'Feriado Municipal'],
  ['Machados', 12, 20, 'Feriado Municipal'],
  ['Orocó', 12, 20, 'Feriado Municipal'],
  ['Passira', 12, 20, 'Feriado Municipal'],
  ['Saloá', 12, 20, 'Feriado Municipal'],
  ['Trindade', 12, 20, 'Feriado Municipal'],
  ['Tupanatinga', 12, 20, 'Feriado Municipal'],
  ['Capoeiras', 12, 21, 'Feriado Municipal'],
  ['Floresta', 12, 22, 'Feriado Municipal'],
  ['Sairé', 12, 23, 'Feriado Municipal'],
  ['Sanharó', 12, 24, 'Feriado Municipal'],
  ['Camocim de São Félix', 12, 29, 'Feriado Municipal'],
  ['Cupira', 12, 29, 'Feriado Municipal'],
  ['Itapetim', 12, 29, 'Feriado Municipal'],
  ['Poção', 12, 29, 'Feriado Municipal'],
  ['Riacho das Almas', 12, 29, 'Feriado Municipal'],
  ['Santa Cruz do Capibaribe', 12, 29, 'Feriado Municipal'],
  ['Toritama', 12, 29, 'Feriado Municipal'],
  ['Carnaíba', 12, 30, 'Feriado Municipal'],
  ['São Vicente Férrer', 12, 30, 'Feriado Municipal'],
  ['Alagoinha', 12, 31, 'Feriado Municipal'],
  ['Ilha de Itamaracá', 12, 31, 'Feriado Municipal'],
  ['Palmeirina', 12, 31, 'Feriado Municipal']
].freeze

# Track statistics
created_count = 0
updated_count = 0
error_count = 0
boundary_not_found = []

# Create holidays
state = Boundary.find_by(level: 4, name: 'Pernambuco')

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
puts 'Pernambuco Municipal Holidays Summary'
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
                 .where('boundaries.level = 4')
                 .where(boundaries: { name: MUNICIPAL_HOLIDAYS.map(&:first).uniq })
                 .group(:name)
                 .count
                 .sort_by { |_, count| -count }

holiday_counts.each do |name, count|
  puts "  #{name}: #{count} municipalities"
end

puts "\n✓ Pernambuco municipal holidays seed completed!"
