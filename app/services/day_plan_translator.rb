# frozen_string_literal: true

# app/services/day_plan_translator.rb
#
# Translates the notes on a single Waypoint into the other two locales.
#
# Takes an explicit source locale so re-running always overwrites the
# translations rather than skipping waypoints that already have all three
# locales populated.
#
# Reads waypoint.notes, translates from the given source locale into the
# other two via the Anthropic API, and saves the result back to the waypoint.
#
# Waypoints with no notes for the given source locale are skipped.
#
# == Usage
#
#   DayPlanTranslator.new(waypoint, source_locale: :en).translate
#   DayPlanTranslator.new(waypoint, source_locale: :es).translate
#
# == Console
#
#   DayPlanTranslator.new(Waypoint.find(42), source_locale: :en).translate
#
class DayPlanTranslator
  MODEL      = 'claude-haiku-4-5-20251001'
  MAX_TOKENS = 8192
  API_URL    = URI('https://api.anthropic.com/v1/messages').freeze

  LOCALES = %w[en es pt].freeze

  LANGUAGE_NAMES = {
    'en' => 'English',
    'es' => 'Spanish (Latin American)',
    'pt' => 'Portuguese (Brazilian)'
  }.freeze

  class TranslationError < StandardError; end
  class InvalidLocaleError < StandardError; end

  # @param waypoint [Waypoint]
  # @param source_locale [String, Symbol] the locale to translate from ('en', 'es', or 'pt')
  def initialize(waypoint, source_locale: :en)
    @waypoint      = waypoint
    @source_locale = source_locale.to_s

    return if LOCALES.include?(@source_locale)

    raise InvalidLocaleError, "Invalid source locale '#{@source_locale}'. Must be one of: #{LOCALES.join(', ')}"
  end

  # Translates from the source locale into the other two and saves them back to the waypoint.
  # Always overwrites the target locales even if they already have content.
  #
  # @return [Boolean] true if translations were saved, false if source notes are blank
  # @raise [TranslationError] if the API call fails or returns an unexpected response
  def translate
    notes       = @waypoint.notes || {}
    source_text = notes[@source_locale].presence

    if source_text.blank?
      Rails.logger.info(
        "[DayPlanTranslator] Waypoint ##{@waypoint.id} (#{@waypoint.name}): " \
        "skipped — no #{@source_locale} notes"
      )
      return false
    end

    target_locales = LOCALES - [@source_locale]

    Rails.logger.info(
      "[DayPlanTranslator] Waypoint ##{@waypoint.id} (#{@waypoint.name}): " \
      "translating from #{@source_locale} into #{target_locales.join(', ')}"
    )

    translations = call_api(source_text, target_locales)

    @waypoint.update!(notes: notes.merge(translations))

    true
  end

  private

  def build_prompt(source_text, target_locales)
    target_descriptions = target_locales.map { |l| "\"#{l}\" (#{LANGUAGE_NAMES[l]})" }.join(' and ')
    source_language     = LANGUAGE_NAMES[@source_locale]

    <<~PROMPT
      You are an editorial travel writer who works across English, Latin American Spanish, and
      Brazilian Portuguese, specialising in South American road trips. You have deep knowledge
      of Brazil (Minas Gerais, Estrada Real) and the Andean altiplano (Bolivia, Peru, Lake Titicaca).

      Below is a day plan narrative written in #{source_language}.
      Produce #{target_descriptions} versions of it.

      ## Translation philosophy

      This is not a word-for-word translation. The goal is natural, idiomatic writing that a
      native speaker would recognise as good prose in their own language. You are re-expressing
      the content, not converting it mechanically. Where the source uses a construction or
      phrasing that would sound foreign or stilted when translated directly, find the equivalent
      that carries the same meaning and tone in the target language.

      Preserve the facts, the historical detail, and the editorial judgement. Change whatever
      is needed at the level of phrasing, sentence structure, and idiom to make it read well.

      ## Idioms and set phrases — the most common failure mode

      English travel writing uses idioms and metaphorical expressions that do not translate
      literally. When you encounter one, do not translate the words — translate the idea.
      Find the construction a native writer would actually use, or rephrase as plain descriptive
      prose if no clean equivalent exists.

      Examples of what NOT to do:

      - "on the waterfront" → "na beira da água" is wrong. Use "à beira do rio", "à beira-mar",
        "no cais", or simply name the place ("no porto", "na orla") depending on context.
      - "the distance feels both smaller and larger than that" → "a distância se sente ao mesmo
        tempo menor e maior" is wrong. "Sentir" used this way is an English calque. Rephrase:
        "a travessia parece mais curta do que é — e ao mesmo tempo mais significativa",
        or simply cut the observation if it cannot be expressed naturally.
      - "it feels like..." → never translate as "parece que se sente" or "se sente como".
        Use "parece", "dá a sensação de", or restructure the sentence entirely.
      - "worth the time" → "vale a pena" in Portuguese/Spanish, not "merece o tempo".

      The test: would a native Brazilian or Latin American writer actually write this sentence?
      If the answer is no, rewrite it until the answer is yes. When in doubt, simpler and more
      direct is better than an attempt at a clever construction that lands awkwardly.

      ## Style conventions to preserve exactly

      **Place name formatting**: Any place name wrapped in __double underscores__ (e.g. __Diamantina__,
      __Posto da Palha__) must remain wrapped in __double underscores__ in every translation.
      Do not remove, replace, or reformat them.

      **Prose only**: No bullet points, no numbered lists, no tables. All content is written
      in flowing paragraphs. Preserve this structure exactly.

      **Markdown structure**: Preserve all ## section headers, blank lines between paragraphs,
      and any bold or italic formatting. Translate header text naturally — use whatever phrasing
      fits the target language best. "## The Drive" might become "## El Camino" or "## A Estrada",
      not a literal word-by-word translation.

      **Tone — editorial, not promotional**: Informed, specific, unhurried. Not enthusiastic or
      marketing-driven. Do NOT use words like "breathtaking", "stunning", "impresionante" (in that
      sense), "deslumbrante", "pristine", "incredible", "incrível", or their equivalents.

      **No personal pronouns**: No "I", "we", "our", "the group", "travelers", "visitors",
      or their equivalents (nosotros, viajeros, visitantes, nós, viajantes, visitantes).
      Narrate the day directly — what exists, what happens, what there is to see.

      **Times as anchors, not schedules**: Use loose, natural phrasing for times. In Spanish,
      prefer "a media mañana", "bien antes del mediodía", "al caer la tarde". In Portuguese,
      prefer "pela manhã", "bem antes do meio-dia", "ao fim da tarde". Only use exact clock
      times when there is a fixed schedule (ferry departure, border crossing, reservation).

      **Historical context**: Translate historical and cultural detail accurately and in full.
      Do not compress or omit context paragraphs. Named places, distances, and specific facts
      must all be preserved.

      ## Measurements

      Apply these rules to every measurement that appears in the source text:

      - **For Spanish and Portuguese translations**: use metric only (km, m, °C).
        Do not include imperial equivalents.
      - **For English source text being read as reference only**: the English notes may contain
        metric with imperial in parentheses — this is correct for English and should be left
        as-is if English is a target, but stripped of imperial when producing Spanish or Portuguese.
      - If a measurement appears in the source only in imperial units, convert to metric for
        Spanish and Portuguese, and express as "X km (Y miles)" or "X m (Y ft)" or "X°C (Y°F)"
        if English is a target locale.

      ## Language register

      - For Spanish: Latin American vocabulary and register, not Castilian. Avoid vosotros.
      - For Portuguese: Brazilian vocabulary and register, not European. Use você, not tu (unless
        the source uses a notably informal register). Prefer Brazilian spelling conventions.
      - In both languages: adapt idioms, connective phrases, and transitions so they feel native,
        not imported from English sentence structure.

      Source text (#{source_language}):
      #{source_text}

      ## Output instructions

      Return ONLY a valid JSON object whose keys are the target locale codes (#{target_locales.map { |l| "\"#{l}\"" }.join(', ')}).
      Each value must be the full translated markdown string.
      Do not include the source language in the response.
      Do not include any text before or after the JSON object.
      Do not wrap the JSON in markdown code fences.

      Example structure (if translating into es and pt):
      {"es": "El Camino\n\n...", "pt": "A Estrada\n\n..."}
    PROMPT
  end

  def call_api(source_text, target_locales)
    prompt = build_prompt(source_text, target_locales)

    request = Net::HTTP::Post.new(API_URL)
    request['Content-Type']      = 'application/json'
    request['x-api-key']         = ENV.fetch('ANTHROPIC_API_KEY')
    request['anthropic-version'] = '2023-06-01'

    request.body = {
      model: MODEL,
      max_tokens: MAX_TOKENS,
      messages: [{ role: 'user', content: prompt }]
    }.to_json

    http = Net::HTTP.new(API_URL.host, API_URL.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise TranslationError,
            "Anthropic API returned HTTP #{response.code}: #{response.body.truncate(500)}"
    end

    parse_response(JSON.parse(response.body, symbolize_names: true), target_locales)
  end

  def parse_response(response, target_locales)
    content = response.dig(:content, 0, :text)
    raise TranslationError, 'Empty response from Anthropic API' if content.blank?

    content = sanitize_json(content)

    result = JSON.parse(content)

    missing = target_locales - result.keys
    raise TranslationError, "Response missing expected locale keys: #{missing.inspect}" unless missing.empty?

    result
  rescue JSON::ParserError => e
    raise TranslationError, "Failed to parse API response as JSON: #{e.message}"
  end

  def sanitize_json(content)
    # Strip markdown fences
    content = content.gsub(/\A```(?:json)?\n?/, '').gsub(/\n?```\z/, '').strip

    # Remove non-printable ASCII control characters except tab (valid in JSON)
    # This intentionally excludes \n and \r — we handle those separately below
    content = content.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, '')

    # Escape literal newlines inside JSON string values.
    # A literal \n or \r inside a JSON string is invalid — it must be \\n / \\r.
    # We do this by scanning character-by-character through string contexts only.
    result  = +''
    in_str  = false
    escaped = false

    content.each_char do |ch|
      if escaped
        result  << ch
        escaped  = false
      elsif ch == '\\'
        result  << ch
        escaped  = true
      elsif ch == '"'
        result  << ch
        in_str   = !in_str
      elsif in_str && ch == "\n"
        result << '\\n'
      elsif in_str && ch == "\r"
        result << '\\r'
      else
        result << ch
      end
    end

    result
  end
end
