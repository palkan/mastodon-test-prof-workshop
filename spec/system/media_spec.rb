# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Media' do
  describe 'Player page' do
    let(:status) { Fabricate :status }

    before do
      Sidekiq.testing!(:fake)

      status.media_attachments << media
    end

    context 'when signed in' do
      before { sign_in Fabricate(:user) }

      context 'when media type is video' do
        let(:media) { Fabricate(:media_attachment, type: :video).tap { |media| media.update_column(:type, :video) } }

        it 'visits the player page and renders media' do
          visit player_medium_path(media)

          expect(page)
            .to have_css('body', class: 'player')
            .and have_css('div[data-component="Video"] video[controls="controls"] source')
        end
      end

      context 'when media type is gifv' do
        let(:media) { Fabricate :media_attachment, type: :gifv }

        it 'visits the player page and renders media' do
          visit player_medium_path(media)

          expect(page)
            .to have_css('body', class: 'player')
            .and have_css('div[data-component="MediaGallery"] video[loop="loop"] source')
        end
      end

      context 'when media type is audio' do
        let(:media) { Fabricate(:media_attachment, type: :audio).tap { |media| media.update_column(:type, :audio) } }

        it 'visits the player page and renders media' do
          visit player_medium_path(media)

          expect(page)
            .to have_css('body', class: 'player')
            .and have_css('div[data-component="Audio"] audio source')
        end
      end
    end
  end
end
