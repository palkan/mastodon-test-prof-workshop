# frozen_string_literal: true

Fabricator(:status_trend) do
  status { |attrs| attrs[:account] ? Fabricate(:status, account: attrs[:account]) : Fabricate(:status) }
  account { |attrs| attrs[:status].account }
end
