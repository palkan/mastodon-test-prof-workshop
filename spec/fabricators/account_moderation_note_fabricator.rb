# frozen_string_literal: true

Fabricator(:account_moderation_note) do
  content { Faker::Lorem.sentences }
  account
  target_account(fabricator: :account)
end
