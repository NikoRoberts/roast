# Roast::Providers::Bedrock Implementation Plan

This document outlines the planned structure and implementation details for the `Roast::Providers::Bedrock` class.

## File Location

`lib/roast/providers/bedrock.rb`

## Class Structure

```ruby
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

      # Interface should be compatible with other Roast providers.
      # It will accept a system prompt, a list of messages, and other
      # optional parameters like temperature and max_tokens.
      def chat(system:, messages:, temperature: 0.2, max_tokens: 1200, **_)
        # 1. Build the request body for the Bedrock API.
        # 2. Call the Bedrock API using @client.invoke_model.
        # 3. Parse the response and extract the content.
        # 4. Handle potential errors from the API.
        # 5. Return a normalized response object.
      end

      private

      def build_messages(msgs)
        # Convert Roast's message format to the format expected by
        # the Bedrock Anthropic Messages API.
      end

      def map_role(role)
        # Map Roast's roles ('user', 'assistant') to the roles
        # expected by the Bedrock API.
      end

      class ProviderError < StandardError; end

      def format_aws_error(e)
        # Format AWS SDK errors into a user-friendly message.
      end
    end
  end
end
```

## Next Steps

1.  **Switch to Code Mode:** The next step is to switch to Code mode to implement this plan.
2.  **Implement the `chat` method:** Fill in the logic for the `chat` method, including building the request body, calling the Bedrock API, and parsing the response.
3.  **Implement helper methods:** Implement the `build_messages` and `map_role` helper methods.
4.  **Add error handling:** Implement the `format_aws_error` method and add robust error handling to the `chat` method.
5.  **Wire up the provider:** Integrate the new provider into the `ApiProviderFactory`.
6.  **Add tests and documentation:** Write unit and integration tests, and update the README.
