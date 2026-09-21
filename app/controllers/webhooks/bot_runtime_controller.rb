# frozen_string_literal: true

class Webhooks::BotRuntimeController < ActionController::API
  before_action :validate_secret

  def postback
    conversation = Conversation.find_by(display_id: params[:conversation_display_id])
    unless conversation
      render json: { error: 'Conversation not found' }, status: :not_found
      return
    end

    agent_bot = find_active_agent_bot(conversation)
    unless agent_bot
      render json: { error: 'No active agent bot for this conversation' }, status: :not_found
      return
    end

    content = params[:content].to_s

    # Resolve media attachments. Prefer the structured attachments the bot_runtime
    # sends; fall back to extracting media URLs from the text (older bot_runtime
    # or other callers). The CRM is the safety net for media detection.
    media = resolve_media(content)
    content = strip_media_urls(content, media) if media.present? && params[:attachments].blank?

    if content.blank? && media.blank?
      render json: { error: 'Content is required' }, status: :bad_request
      return
    end

    content_type = params[:content_type].presence || 'text'
    raw_items    = params[:items]
    content_attributes = nil

    if content_type == 'input_select' && raw_items.present?
      items = raw_items.map { |item| { title: item[:title].to_s, value: item[:value].to_s } }
      content_attributes = { items: items }
    end

    message = AgentBots::MessageCreator.new(agent_bot).create_bot_reply(
      content, conversation,
      content_type: content_type,
      content_attributes: content_attributes,
      media: media
    )

    if message
      Rails.logger.info "[BotRuntime::Postback] Message created: #{message.id} conversation=#{conversation.display_id}"
      render json: { status: 'sent' }, status: :ok
    else
      Rails.logger.warn "[BotRuntime::Postback] Message creation failed: conversation=#{conversation.display_id}"
      render json: { error: 'Message creation failed' }, status: :unprocessable_entity
    end
  end

  private

  VALID_MEDIA_FILE_TYPES = %w[image audio video file].freeze

  def resolve_media(content)
    if params[:attachments].present?
      Array(params[:attachments]).filter_map do |att|
        url = att[:url].to_s
        file_type = att[:file_type].to_s
        next if url.blank?
        next unless VALID_MEDIA_FILE_TYPES.include?(file_type)

        { url: url, file_type: file_type }
      end
    else
      AgentBots::MediaUrlExtractor.call(content)[:media]
    end
  end

  def strip_media_urls(content, media)
    AgentBots::MediaUrlExtractor.call(content)[:text]
  end

  def validate_secret
    expected_secret = BotRuntime::Config.secret
    return if expected_secret.blank?

    provided_secret = request.headers['X-Bot-Runtime-Secret']
    return if provided_secret == expected_secret

    render json: { error: 'Unauthorized' }, status: :unauthorized
  end

  # Stage-aware agent bot resolution (mirrors AgentBotListener#resolve_stage_agent_bot).
  # Falls back to inbox agent_bot when the stage has no agent_bot configured.
  def find_active_agent_bot(conversation)
    inbox = conversation.inbox
    agent_bot_inbox = inbox.agent_bot_inbox
    return nil unless agent_bot_inbox&.active?

    # Try stage-based routing first
    stage_bot = resolve_stage_agent_bot(conversation)
    return stage_bot if stage_bot

    # Legacy fallback: inbox agent_bot
    agent_bot_inbox.agent_bot
  end

  def resolve_stage_agent_bot(conversation)
    pipeline_item = conversation.pipeline_items.first
    return nil unless pipeline_item

    stage = pipeline_item.pipeline_stage
    return nil unless stage
    return nil unless stage.agent_bot

    # If the stage has a required_label, the conversation must have it
    if stage.required_label_id.present?
      required_label = stage.required_label
      unless conversation_has_label?(conversation, required_label)
        Rails.logger.info "[BotRuntime::Postback] Stage #{stage.name} requires label '#{required_label.title}' but conversation #{conversation.id} doesn't have it — silencing"
        return nil
      end
    end

    Rails.logger.info "[BotRuntime::Postback] Stage-based routing: stage='#{stage.name}' agent_bot='#{stage.agent_bot.name}' (ID: #{stage.agent_bot.id})"
    stage.agent_bot
  end

  def conversation_has_label?(conversation, label)
    tag_names = conversation.label_list || []
    tag_names.any? do |name|
      name == label.id.to_s || name == label.title
    end
  end
end
