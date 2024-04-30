require "test_prof/any_fixture/dsl"
using TestProf::AnyFixture::DSL

require "test_prof/ext/active_record_refind"
using TestProf::Ext::ActiveRecordRefind

RSpec.shared_context "shared:account" do
  if ENV["SLOW_MY_TESTS"]
    let!(:account) { Fabricate(:account) }
  else
    let_it_be(:account) { Fabricate(:account) }
  end
end

RSpec.shared_context "shared:user" do
  if ENV["SLOW_MY_TESTS"]
    let!(:user) { Fabricate(:user) }
  else
    let_it_be(:user) { Fabricate(:user) }
  end
end

RSpec.shared_context "shared:admin" do
  let(:role) { UserRole.find_by(name: 'Admin') }

  if ENV["SLOW_MY_TESTS"]
    let!(:user) { Fabricate(:user, role: role) }
  else
    let_it_be(:user) { Fabricate(:user) }

    before { user.update!(role: role) }
  end
end

RSpec.shared_context "shared:moderator" do
  let(:role) { UserRole.find_by(name: 'Moderator') }

  if ENV["SLOW_MY_TESTS"]
    let!(:user) { Fabricate(:user, role: role) }
  else
    let_it_be(:user) { Fabricate(:user) }
    before { user.update!(role: role) }
  end
end

RSpec.shared_context "shared:status" do
  if ENV["SLOW_MY_TESTS"]
    let!(:status) { Fabricate(:status) }
  else
    let_it_be(:status) { Fabricate(:status) }
  end
end

RSpec.configure do |config|
  config.include_context "shared:account", account: true
  config.include_context "shared:user", user: true
  config.include_context "shared:admin", admin: true
  config.include_context "shared:moderator", moderator: true
  config.include_context "shared:status", status: true
end
