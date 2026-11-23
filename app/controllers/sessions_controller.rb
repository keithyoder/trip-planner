# frozen_string_literal: true

# Devise only generates session routes for database_authenticatable, which this
# app doesn't use, so login/logout are plain controller actions.
class SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'welcome'

  def new
    redirect_to trips_path if user_signed_in?
  end

  def destroy
    sign_out(:user)
    redirect_to root_path, notice: t('auth.signed_out'), status: :see_other
  end
end
