# frozen_string_literal: true

require "bundler/inline"

gemfile(true, quiet: true) do
  source "https://rubygems.org"

  gem "octokit"
  gem "base64"
end

ISSUE_NUMBER = ENV.fetch("GITHUB_ISSUE_NUMBER")
REPO = ENV.fetch("GITHUB_REPOSITORY")

@client = Octokit::Client.new(access_token: ENV.fetch("GITHUB_TOKEN"))

issue = @client.issue(@repo, issue_number)
issue_body = issue.body

puts issue_body
