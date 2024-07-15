Spree::Core::Engine.add_routes do
  # Add your extension routes here
  resources :paypal_checkout, only: :create
end