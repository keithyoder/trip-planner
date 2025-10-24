source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.7'

gem 'activerecord-postgis-adapter'
gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0'
gem 'capistrano'
gem 'capistrano-bundler', require: false
gem 'capistrano-passenger', require: false
gem 'capistrano-rails', require: false
gem 'capistrano-rbenv', require: false
gem 'chartkick'
gem 'cssbundling-rails'
gem 'devise'
gem 'dotenv-rails', groups: %i[development test]
gem 'ed25519', '>= 1.2', '< 2.0'
gem 'geocoder'
gem 'jbuilder'
gem 'jsbundling-rails'
gem 'money'
gem 'omniauth'
gem 'omniauth-google-oauth2'
gem 'omniauth-rails_csrf_protection'
gem 'overpass-api-ruby', git: 'https://github.com/Toucouleur66/overpass-api-ruby'
gem 'pg'
gem 'puma', '~> 6.0'
gem 'rails', '~> 7.1'
gem 'redis', '~> 4.0'
gem 'rgeo-geojson'
gem 'rosemary'
gem 'rubocop'
gem 'scenic', '1.8.0'
gem 'slim'
gem 'sprockets-rails'
gem 'stimulus-rails'
gem 'turbo-rails'

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Use Sass to process CSS
# gem "sassc-rails"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug', platforms: %i[mri mingw x64_mingw]
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'web-console'

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem 'capybara'
  gem 'selenium-webdriver'
end
