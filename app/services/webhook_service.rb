# frozen_string_literal: true

class WebhookService < BaseService
  def call(event, object)
    @event = Webhooks::EventPresenter.new(event, object)
    webhook_ids = webhooks_for_event
    return if webhook_ids.empty?

    @body = serialize_event

    webhook_ids.each do |webhook_id|
      Webhooks::DeliveryWorker.perform_async(webhook_id, @body)
    end
  end

  private

  def webhooks_for_event
    Webhook.enabled.where('? = ANY(events)', @event.type).pluck(:id)
  end

  def serialize_event
    ActiveModelSerializers::SerializableResource
      .new(@event, serializer: REST::Admin::WebhookEventSerializer, scope: nil, scope_name: :current_user)
      .to_json
  end
end
