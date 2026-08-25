# frozen_string_literal: true

Fabricator(:quote) do
  status
  quoted_status(fabricator: :status)
  state :pending
end
