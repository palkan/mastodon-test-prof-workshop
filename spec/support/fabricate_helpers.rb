# frozen_string_literal: true

# Lightweight helpers used by fabricators to avoid Fabrication's schematic
# evaluation overhead (`BasicObject#instance_exec` chain, ~15 ms per nested
# `Fabricate.build`) where a plain model instantiation with the same
# defaults is sufficient (~1 ms).
#
# IMPORTANT: These helpers must mirror the defaults of the corresponding
# fabricators 1:1. When a fabricator default changes, update the helper too.
module FabricateHelpers
  class << self
    # Memoized role lookup. The DB seed creates the canonical Admin/
    # Moderator/Owner roles once per suite run; hundreds of fabrications
    # otherwise issue the same SELECT each time.
    def role(name)
      (@role_cache ||= {})[name] ||= UserRole.find_by(name:)
    end

    # A drop-in replacement for Fabricate.build(:user, account: nil) with the
    # identical defaults to the :user fabricator. Keeps its own email counter
    # (`helper_user_N@example.com`) to preserve uniqueness across files
    # (Fabrication sequences are global counters, so both paths stay
    # monotonic).
    def build_user(attrs = {})
      @email_seq = 0 unless defined?(@email_seq)
      @email_seq += 1
      overrides = { account: nil }.merge(attrs)
      User.new({
        email: "helper_user_#{@email_seq}@example.com",
        password: '123456789',
        confirmed_at: Time.zone.now,
        current_sign_in_at: Time.zone.now,
        agreement: true,
      }.merge(overrides))
    end
  end
end
