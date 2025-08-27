# frozen_string_literal: true
require 'aws-sdk-bedrockruntime'
require 'json'

module Roast
  module Providers
    class Bedrock
      DEFAULT_MODEL = ENV.fetch('BEDROCK_MODEL_ID', 'anthropic.claude-3-sonnet-20240229-v1:0')
      DEFAULT_REGION = ENV.fetch('AWS_REGION', 'us-east-1')

      def initialize(model: DEFAULT_MODEL, region: DEFAULT_REGION, logger: nil, **opts)
        @model_id = model
        @logger   = logger
        @client   = Aws::BedrockRuntime::Client.new(region: region)
        @opts     = opts
      end

      # expected signature should mirror the other providers
      # params: system:, messages:, temperature:, max_tokens:, stop: nil, …
      def chat(system:, messages:, temperature: 0.2, max_tokens: 1200, **_)
        body = {
          anthropic_version: 'bedrock-2023-05-31',
          system: system.to_s,
          messages: build_messages(messages),
          max_tokens: max_tokens.to_i,
          temperature: temperature.to_f
        }

        resp = @client.invoke_model(
          model_id: @model_id,
          content_type: 'application/json',
          accept: 'application/json',
          body: JSON.dump(body)
        )

        parsed = JSON.parse(resp.body.read)
        text = parsed.dig('content', 0, 'text') || ''
        {
          text: text,
          # include optional usage fields if Roast expects them; parse from response if present
        }
      rescue Aws::BedrockRuntime::Errors::ServiceError => e
        raise ProviderError, format_aws_error(e)
      rescue JSON::ParserError => e
        raise ProviderError, "Bedrock returned invalid JSON: #{e.message}"
      end

      private

      def build_messages(msgs)
        # msgs is expected to be an array of {role: 'user'|'assistant'|'system', content: '...'}
        msgs
          .reject { |m| m[:role].to_s == 'system' } # system handled separately
          .map do |m|
            {
              role: map_role(m[:role]),
              content: [{ type: 'text', text: m[:content].to_s }]
            }
          end
      end

      def map_role(role)
        r = role.to_s
        return 'user' if r == 'user'
        return 'assistant' if r == 'assistant'
        'user'
      end

      class ProviderError < StandardError; end

      def format_aws_error(e)
        code = e.code rescue nil
        "#{code || 'BedrockError'}: #{e.message}"
      end
    end
  end
end
