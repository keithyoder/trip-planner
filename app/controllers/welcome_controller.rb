# frozen_string_literal: true

# The public landing page. Everything on it is computed on the server (see
# Landing::Overview) so it is right on first load, without JavaScript.
class WelcomeController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_admin!
  layout 'public'

  def index
    @overview = Landing::Overview.build
    @map = @overview.map
    @social_links = Rails.application.config_for(:social_links)
  end
end
