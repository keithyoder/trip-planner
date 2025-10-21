require 'json'
require "i18n"

file = File.read('/Users/keithyoder/Downloads/peru-4.geojson')
data_hash = JSON.parse(file)
data_hash['features'].each do |data|
  query = <<-SQL 
    INSERT INTO boundaries (name, level, geom, created_at, updated_at, hierarchy)
    VALUES (
        '#{data['properties']['local_name'].gsub(/'/, "''")}',
        #{data['properties']['admin_level']},
        ST_Multi(ST_GeomFromGeoJson('#{data['geometry'].to_json}')),
        current_timestamp,
        current_timestamp,
        ('south_america.peru.#{I18n.transliterate(data['properties']['local_name'].downcase.gsub(/'/, "_").gsub(' ', '_'))}')::ltree
    )
    SQL

    result = ActiveRecord::Base.connection.execute(query)
end