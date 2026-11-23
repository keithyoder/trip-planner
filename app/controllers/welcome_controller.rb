# frozen_string_literal: true

class WelcomeController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'welcome'

  def index
    # Add any logic needed for the welcome page
  end
end
