# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

# Once the suite passes 50 tests Rails runs it in forked worker processes. On
# macOS, libpq (bundled in the pg gem) segfaults when it opens a connection in a
# forked child unless GSS encryption negotiation is off, and the parent then
# waits forever on the dead worker. Harmless elsewhere.
ENV['PGGSSENCMODE'] ||= 'disable'

require_relative '../config/environment'
require 'rails/test_help'

Dir[Rails.root.join('test/support/**/*.rb')].each { |f| require f }

# Fixtures delete and reinsert rows, and DATABASE_URL (from dotenv or the shell)
# overrides database.yml, so refuse to run against anything but a local database.
test_host = ActiveRecord::Base.connection_db_config.host.to_s
unless test_host.empty? || %w[localhost 127.0.0.1 ::1].include?(test_host) || test_host.start_with?('/')
  abort "Refusing to run tests against non-local database host #{test_host.inspect}"
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# The whole app is behind Devise sign-in, so controller/integration tests call
# `sign_in users(:keith)` in setup. There are no passwords (Google-only), which
# is why this uses Warden's test helpers rather than posting credentials.
module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers
  end
end
