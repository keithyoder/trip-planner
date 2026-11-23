# frozen_string_literal: true

# The users table already exists in production (it was created outside of a
# migration when Google sign-in was first sketched), so every statement here is
# guarded with if_not_exists: this is a no-op there and only builds the table
# for fresh databases (local dev, test, CI).
class CreateUsers < ActiveRecord::Migration[7.2]
  # rubocop:disable Metrics/MethodLength -- a table definition reads best in one block
  def change
    create_table :users, if_not_exists: true do |t|
      t.string :email, null: false, default: ''
      t.string :provider
      t.string :uid
      t.string :name
      t.string :avatar_url

      # Devise :trackable
      t.integer :sign_in_count, null: false, default: 0
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string :current_sign_in_ip
      t.string :last_sign_in_ip

      t.timestamps
    end

    add_index :users, :email, unique: true, if_not_exists: true
    add_index :users, %i[provider uid], unique: true, if_not_exists: true
  end
  # rubocop:enable Metrics/MethodLength
end
