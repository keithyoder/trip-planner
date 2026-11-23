# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
  devise_scope :user do
    # Devise's failure app redirects to new_user_session, so this name is required.
    get '/login', to: 'sessions#new', as: :new_user_session
    delete '/logout', to: 'sessions#destroy', as: :destroy_user_session
  end

  root 'welcome#index'
  post '/locale/:locale', to: 'locales#update', as: :locale
  get 'routes/new'
  get 'dashboard', to: 'dashboard#index'
  # The read-only side: what viewers (non-admins) see after signing in.
  get 'follow', to: 'follow#index'
  get 'follow/routes/:id', to: 'follow/routes#show', as: :follow_route

  resources :trip_logs, only: %i[index show] do
    collection do
      get :today
    end
  end

  resources :stops, only: %i[edit update] do
    resources :expenses, only: [:create] do
      collection do
        post :from_receipt
      end
    end
  end

  resources :trips do
    resources :waypoints
    resources :routes do
      member do
        get :network_coverage
        post :calculate
        post :generate_day_plan
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
    resource :budget, only: :show
    member do
      get :currencies
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
end
