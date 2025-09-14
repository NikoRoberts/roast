# frozen_string_literal: true

require "test_helper"

module Roast
  module Workflow
    class WorkflowInitializerBedrockTest < ActiveSupport::TestCase
      def setup
        @original_aws_region = ENV["AWS_REGION"]
        @original_aws_profile = ENV["AWS_PROFILE"]
        @original_aws_access_key = ENV["AWS_ACCESS_KEY_ID"]
        @original_aws_secret_key = ENV["AWS_SECRET_ACCESS_KEY"]
      end

      def teardown
        ENV["AWS_REGION"] = @original_aws_region
        ENV["AWS_PROFILE"] = @original_aws_profile
        ENV["AWS_ACCESS_KEY_ID"] = @original_aws_access_key
        ENV["AWS_SECRET_ACCESS_KEY"] = @original_aws_secret_key
      end

      def test_detects_bedrock_anthropic_models
        configuration = mock_configuration(model: "anthropic.claude-3-sonnet-20240229-v1:0")
        initializer = WorkflowInitializer.new(configuration)

        assert(initializer.send(:is_bedrock_model?, "anthropic.claude-3-sonnet-20240229-v1:0"))
        refute(initializer.send(:is_bedrock_model?, "claude-3-5-sonnet-20241022"))
      end

      def test_detects_bedrock_amazon_models
        configuration = mock_configuration(model: "amazon.titan-text-express-v1")
        initializer = WorkflowInitializer.new(configuration)

        assert(initializer.send(:is_bedrock_model?, "amazon.titan-text-express-v1"))
      end

      def test_detects_bedrock_meta_models
        configuration = mock_configuration(model: "meta.llama2-70b-chat-v1")
        initializer = WorkflowInitializer.new(configuration)

        assert(initializer.send(:is_bedrock_model?, "meta.llama2-70b-chat-v1"))
      end

      def test_configure_bedrock_with_region_only
        configuration = mock_configuration(model: "anthropic.claude-3-sonnet-20240229-v1:0")
        initializer = WorkflowInitializer.new(configuration)

        initializer.send(:configure_bedrock_env, "us-east-1")

        assert_equal("us-east-1", ENV["AWS_REGION"])
      end

      def test_configure_bedrock_with_json_credentials
        configuration = mock_configuration(model: "anthropic.claude-3-sonnet-20240229-v1:0")
        initializer = WorkflowInitializer.new(configuration)

        json_config = '{"region":"us-west-2","access_key":"AKIA123","secret_key":"secret123"}'
        initializer.send(:configure_bedrock_env, json_config)

        assert_equal("us-west-2", ENV["AWS_REGION"])
        assert_equal("AKIA123", ENV["AWS_ACCESS_KEY_ID"])
        assert_equal("secret123", ENV["AWS_SECRET_ACCESS_KEY"])
      end

      def test_configure_bedrock_with_profile_name
        configuration = mock_configuration(model: "anthropic.claude-3-sonnet-20240229-v1:0")
        initializer = WorkflowInitializer.new(configuration)

        initializer.send(:configure_bedrock_env, "production")

        assert_equal("production", ENV["AWS_PROFILE"])
      end

      private

      def mock_configuration(model: nil, api_provider: :ruby_llm, api_token: nil)
        config = mock("Configuration")
        config.stubs(:model).returns(model)
        config.stubs(:api_provider).returns(api_provider)
        config.stubs(:api_token).returns(api_token)
        config
      end
    end
  end
end