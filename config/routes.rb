# frozen_string_literal: true

Rails.application.routes.draw do
  # devise_for :users, controllers: {
  #   omniauth_callbacks: 'users/omniauth_callbacks'
  # }

  root 'welcome#index'
  post '/locale/:locale', to: 'locales#update', as: :locale
  get 'routes/new'
  get 'dashboard', to: 'dashboard#index'

  resources :trip_logs, only: %i[index show] do
    collection do
      get :today
    end
  end

  resources :trips do
    resources :waypoints
    resources :routes do
      member do
        post :calculate
      end
      resources :overpass, param: :type, only: %i[index show] do
        collection do
          post :create
        end
        member do
          post :import_waypoint
        end
      end
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
end
