# frozen_string_literal: true

Fabricator(:instance_moderation_note) do
  domain { sequence(:domain) { |i| "#{i}#{Faker::Internet.domain_name}" } }
  account
  content { Faker::Lorem.sentence }
end
