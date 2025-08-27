# typed: false
# frozen_string_literal: true

require "test_helper"
require "roast/providers/bedrock"

module Roast
  module Providers
    class BedrockTest < Minitest::Test
      def setup
        # Stub AWS credentials to prevent network requests
        Aws.config[:credentials] = Aws::Credentials.new("test-key", "test-secret")
      end

      def test_chat_completion
        # Mock the Bedrock client
        mock_client = Minitest::Mock.new
        mock_response = Minitest::Mock.new
        mock_body = StringIO.new({ content: [{ text: "LGTM" }] }.to_json)

        mock_response.expect(:body, mock_body)
        mock_client.expect(:invoke_model, mock_response) do |args|
          args.is_a?(Hash)
        end

        # Stub the client initialization
        Aws::BedrockRuntime::Client.stub(:new, mock_client) do
          provider = Roast::Providers::Bedrock.new
          out = provider.chat(
            system: "system msg",
            messages: [
              { role: 'user', content: 'hello' },
              { role: 'assistant', content: 'hi' },
              { role: 'user', content: 'review this diff: ...' }
            ],
            temperature: 0.1,
            max_tokens: 256
          )

          assert_equal("LGTM", out[:text])
        end
      end

      def test_handles_aws_errors
        # Mock the Bedrock client to raise an error
        mock_client = Minitest::Mock.new
        mock_client.expect(:invoke_model, nil) do
          raise Aws::BedrockRuntime::Errors::ThrottlingException.new(nil, 'throttled')
        end

        # Stub the client initialization
        Aws::BedrockRuntime::Client.stub(:new, mock_client) do
          provider = Roast::Providers::Bedrock.new
          assert_raises(Roast::Providers::Bedrock::ProviderError, /throttled/i) do
            provider.chat(system: '', messages: [])
          end
        end
      end
    end
  end
end
