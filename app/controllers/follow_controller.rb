# frozen_string_literal: true

# Home of the read-only pages: the list of days. Any signed-in user may see
# these, so they opt out of the admin requirement; nothing here may change data.
class FollowController < ApplicationController
  skip_before_action :require_admin!
  layout 'public'

  def index
    @overview = Landing::Overview.build
    @map = @overview.map
    @days = Follow::Days.new(@overview.trip, today: @overview.today).call
  end
end
