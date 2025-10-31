# frozen_string_literal: true

json.array! @trips, partial: 'trips/trip', as: :trip
