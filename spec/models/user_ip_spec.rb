# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserIp do
  describe 'Scopes' do
    describe '.by_latest_used' do
      let!(:user) { Fabricate :user, sign_up_ip: '192.168.0.1', created_at: 15.days.ago }
      let!(:other_user) { Fabricate :user, sign_up_ip: '10.0.10.0', created_at: 10.days.ago }

      it 'returns records ordered by most recent usage' do
        expect(described_class.by_latest_used.where(ip: [user.sign_up_ip, other_user.sign_up_ip]).map(&:ip))
          .to eq([IPAddr.new('10.0.10.0'), IPAddr.new('192.168.0.1')])
      end
    end

    describe '.contained_by' do
      let!(:user) { Fabricate :user, sign_up_ip: '192.168.0.1' }
      let!(:other_user) { Fabricate :user, sign_up_ip: '10.0.10.0' }

      it 'returns records ordered by rank' do
        expect(described_class.contained_by('192.168.0.0/24').map(&:ip))
          .to include(IPAddr.new('192.168.0.1'))
          .and not_include(IPAddr.new('10.0.10.0'))
      end
    end
  end
end
