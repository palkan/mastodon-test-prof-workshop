# frozen_string_literal: true

Fabricator(:collection_item) do
  collection
  account
  position                  { sequence(:position, 1) }
  state                     :accepted
end

Fabricator(:unverified_remote_collection_item, from: :collection_item) do
  account      nil
  state        :pending
  object_uri   { Fabricate.build(:remote_account).uri }
  uri { sequence(:uri) { |i| "https://example.com/collection_items/#{i}" } }
end
