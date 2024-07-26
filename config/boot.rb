# frozen_string_literal: true

unless ENV.key?('RAILS_ENV')
  abort <<~ERROR
    The RAILS_ENV environment variable is not set.

    Please set it correctly depending on context:

      - Use "production" for a live deployment of the application
      - Use "development" for local feature work
      - Use "test" when running the automated spec suite
  ERROR
end

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.
# Speed up boot time by caching expensive operations.
# Snippet from https://github.com/Shopify/bootsnap
require 'bootsnap'
env = ENV['RAILS_ENV'] || "development"
Bootsnap.setup(
  cache_dir:            ENV.fetch("BOOTSNAP_CACHE_DIR", "tmp/cache"),
  development_mode:     env == 'development',
  load_path_cache:      true,
  compile_cache_iseq:   true,
  compile_cache_yaml:   false,
  compile_cache_json:   false
)
