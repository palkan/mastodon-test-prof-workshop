RSpec.shared_context "shared:account" do
  let_it_be(:account) { Fabricate(:account) }
end

RSpec.shared_context "shared:user" do
  let_it_be(:user) { Fabricate(:user) }
end

RSpec.shared_context "shared:admin" do
  let(:role) { UserRole.find_by(name: 'Admin') }
  let_it_be(:user) { Fabricate(:user) }

  before { user.update!(role: role) }
end

RSpec.shared_context "shared:moderator" do
  let(:role) { UserRole.find_by(name: 'Moderator') }
  let_it_be(:user) { Fabricate(:user) }

  before { user.update!(role: role) }
end

RSpec.shared_context "shared:status" do
  let_it_be(:status) { Fabricate(:status) }
end

RSpec.configure do |config|
  config.include_context "shared:account", account: true
  config.include_context "shared:user", user: true
  config.include_context "shared:admin", admin: true
  config.include_context "shared:moderator", moderator: true
  config.include_context "shared:status", status: true
end
