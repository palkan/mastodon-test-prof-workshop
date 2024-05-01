# frozen_string_literal: true

require 'rails_helper'

describe ActivityPub::ClaimsController, :account do
  describe 'POST #create' do
    context 'without signature' do
      before do
        post :create, params: { account_username: account.username }, body: '{}'
      end

      it 'returns http not authorized' do
        expect(response).to have_http_status(401)
      end
    end
  end
end
