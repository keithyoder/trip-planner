# frozen_string_literal: true

# Helper module for titleizing Portuguese place names with proper accents
# and lowercase prepositions
module PortugueseTitleize
  # Portuguese prepositions that should remain lowercase (except at start)
  PREPOSITIONS = %w[do da dos das de e].freeze

  # Common Portuguese words that need accent restoration
  # This is not exhaustive but covers most Pernambuco municipalities
  ACCENT_MAP = {
    'afranio' => 'Afrânio',
    'agua' => 'Água',
    'aguas' => 'Águas',
    'alianca' => 'Aliança',
    'belem' => 'Belém',
    'bodoco' => 'Bodocó',
    'brejao' => 'Brejão',
    'buique' => 'Buíque',
    'cabrobo' => 'Cabrobó',
    'caetes' => 'Caetés',
    'carnaiba' => 'Carnaíba',
    'cha' => 'Chã',
    'custodia' => 'Custódia',
    'fatima' => 'Fátima',
    'felix' => 'Félix',
    'gloria' => 'Glória',
    'goita' => 'Goitá',
    'gravata' => 'Gravatá',
    'iguaraci' => 'Iguaracy',
    'inaja' => 'Inajá',
    'itaiba' => 'Itaíba',
    'itamaraca' => 'Itamaracá',
    'itambe' => 'Itambé',
    'jaboatao' => 'Jaboatão',
    'jatoba' => 'Jatobá',
    'jatauba' => 'Jataúba',
    'joao' => 'João',
    'jose' => 'José',
    'lourenco' => 'Lourenço',
    'moreilandia' => 'Moreilândia',
    'nazare' => 'Nazaré',
    'oroco' => 'Orocó',
    'orobo' => 'Orobó',
    'paraiba' => 'Paraíba',
    'petrolandia' => 'Petrolândia',
    'pocao' => 'Poção',
    'quipapa' => 'Quipapá',
    'ribeirao' => 'Ribeirão',
    'saire' => 'Sairé',
    'saloa' => 'Saloá',
    'sanharo' => 'Sanharó',
    'sao' => 'São',
    'sertania' => 'Sertânia',
    'sirinhaem' => 'Sirinhaém',
    'tamandare' => 'Tamandaré',
    'timbauba' => 'Timbaúba',
    'vicencia' => 'Vicência',
    'vitoria' => 'Vitória',
    'santo' => 'Santo',
    'antao' => 'Antão'
  }.freeze

  # Titleize a Portuguese place name with proper accent restoration
  # and lowercase prepositions
  #
  # @param name [String] The name to titleize (can be ALL CAPS or any case)
  # @return [String] Properly titleized name
  #
  # Examples:
  #   titleize('SAO BENTO DO UNA') #=> 'São Bento do Una'
  #   titleize('CABO DE SANTO AGOSTINHO') #=> 'Cabo de Santo Agostinho'
  #   titleize('BELEM DE SAO FRANCISCO') #=> 'Belém de São Francisco'
  def self.titleize(name)
    return name if name.nil? || name.empty?

    words = name.downcase.split(/[\s-]+/)

    words.map.with_index do |word, index|
      # Always capitalize first word
      if index.zero?
        ACCENT_MAP[word] || word.capitalize
      # Keep prepositions lowercase (unless first word)
      elsif PREPOSITIONS.include?(word)
        word
      # Use accent map or capitalize
      else
        ACCENT_MAP[word] || word.capitalize
      end
    end.join(' ')
  end

  # Batch titleize multiple names
  #
  # @param names [Array<String>] Array of names to titleize
  # @return [Array<String>] Array of titleized names
  def self.titleize_all(names)
    names.map { |name| titleize(name) }
  end

  # Create a mapping hash from old names to new titleized names
  #
  # @param names [Array<String>] Array of ALL CAPS names
  # @return [Hash] Mapping of old names to titleized names
  def self.create_mapping(names)
    names.each_with_object({}) do |name, hash|
      hash[name] = titleize(name)
    end
  end
end

# Example usage:
if __FILE__ == $PROGRAM_NAME
  require 'pp'

  test_names = [
    'SAO BENTO DO UNA',
    'BELEM DE SAO FRANCISCO',
    'JABOATAO DOS GUARARAPES',
    'CABO DE SANTO AGOSTINHO',
    'GLORIA DO GOITA',
    'VITORIA DE SANTO ANTAO',
    'CHA GRANDE',
    'RECIFE',
    'OLINDA',
    'SAO JOSE DO EGITO'
  ]

  puts 'Testing Portuguese titleization:'
  puts '=' * 70
  test_names.each do |name|
    titleized = PortugueseTitleize.titleize(name)
    puts "#{name.ljust(35)} => #{titleized}"
  end

  puts "\n✓ All tests completed"
end
