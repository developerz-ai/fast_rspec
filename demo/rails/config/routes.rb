Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :posts, only: %i[index show new create] do
    patch :publish, on: :member
    resources :comments, only: :create
  end
  get "stats" => "posts#stats", as: :stats
  get "weather" => "weather#show", as: :weather

  root "posts#index"
end
