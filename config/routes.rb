# frozen_string_literal: true

Rails.application.routes.draw do
  root 'welcome#index'
  get 'routes/new'
  resources :trips do
    resources :waypoints
    resources :routes
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
end
