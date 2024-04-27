# frozen_string_literal: true

encrypted_password = Devise::Encryptor.digest(User, '123456789')

Fabricator(:user) do
  account      { Fabricate.build(:account, user: nil) }
  email        { sequence(:email) { |i| "#{i}#{Faker::Internet.email}" } }
  encrypted_password encrypted_password
  confirmed_at { Time.zone.now }
  current_sign_in_at { Time.zone.now }
  agreement true
end
