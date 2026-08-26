# frozen_string_literal: true

Fabricator(:notification_request) do
  account
  from_account { |attrs| attrs[:last_status]&.account || Fabricate(:account) }
  last_status { |attrs| Fabricate(:status, account: attrs[:from_account]) }
end
