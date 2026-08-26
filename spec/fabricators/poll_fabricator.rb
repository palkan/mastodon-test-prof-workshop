# frozen_string_literal: true

Fabricator(:poll) do
  status { |attrs| attrs[:account] ? Fabricate(:status, account: attrs[:account]) : Fabricate(:status) }
  account { |attrs| attrs[:status].account }
  expires_at  { 7.days.from_now }
  options     %w(Foo Bar)
  multiple    false
  hide_totals false
end
