# frozen_string_literal: true

require 'test_helper'

# A chromedriver found on PATH (e.g. a Homebrew cask) takes precedence over the
# one Selenium Manager downloads to match the installed Chrome, and a stale one
# fails with "only supports Chrome version N". CHROMEDRIVER_PATH pins a specific
# binary when that happens; unset, Selenium picks the driver itself.
Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch('CHROMEDRIVER_PATH') if ENV['CHROMEDRIVER_PATH']

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
end
