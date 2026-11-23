# frozen_string_literal: true

require 'test_helper'

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    test 'rejects sockets with no signed-in user' do
      assert_reject_connection { connect }
    end

    test 'accepts a socket whose session has a signed-in user' do
      user = User.create!(email: 'me@example.com')
      warden = Struct.new(:user_obj) { def user(_scope = nil) = user_obj }.new(user)

      connect env: { 'warden' => warden }

      assert_equal user, connection.current_user
    end
  end
end
