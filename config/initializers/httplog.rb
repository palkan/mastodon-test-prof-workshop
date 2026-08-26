# frozen_string_literal: true

# Disable in production unless log level is `debug`. Skip test: request specs
# do not assert on HttpLog output and the Net::HTTP wrapper is extra cost.
if !Rails.env.test? && (Rails.env.local? || Rails.logger.debug?)
  require 'httplog'

  HttpLog.configure do |config|
    config.logger = Rails.logger
    config.color = { color: :yellow }
    config.compact_log = true
  end
end
