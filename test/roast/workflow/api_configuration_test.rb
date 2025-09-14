# frozen_string_literal: true

require "test_helper"

module Roast
  module Workflow
    class ApiConfigurationTest < ActiveSupport::TestCase
      def setup
        @original_openai_key = ENV["OPENAI_API_KEY"]
        @original_openrouter_key = ENV["OPENROUTER_API_KEY"]
        @original_ruby_llm_key = ENV["RUBY_LLM_API_KEY"]
        @original_anthropic_key = ENV["ANTHROPIC_API_KEY"]
      end

      def teardown
        ENV["OPENAI_API_KEY"] = @original_openai_key
        ENV["OPENROUTER_API_KEY"] = @original_openrouter_key
        ENV["RUBY_LLM_API_KEY"] = @original_ruby_llm_key
        ENV["ANTHROPIC_API_KEY"] = @original_anthropic_key
      end

      def test_initializes_with_config_hash
        config = { "api_provider" => "openai" }
        api_config = ApiConfiguration.new(config)
        assert_equal(:openai, api_config.api_provider)
      end

      def test_processes_api_token_from_config
        config = { "api_token" => "test-token" }
        api_config = ApiConfiguration.new(config)
        assert_equal("test-token", api_config.api_token)
      end

      def test_processes_shell_command_api_token
        config = { "api_token" => "$(echo secret-token)" }
        ResourceResolver.expects(:process_shell_command).with("$(echo secret-token)").returns("secret-token")

        api_config = ApiConfiguration.new(config)
        assert_equal("secret-token", api_config.api_token)
      end

      def test_openai_predicate
        config = { "api_provider" => "openai" }
        api_config = ApiConfiguration.new(config)

        assert(api_config.openai?)
        refute(api_config.openrouter?)
        refute(api_config.ruby_llm?)
      end

      def test_openrouter_predicate
        config = { "api_provider" => "openrouter" }
        api_config = ApiConfiguration.new(config)

        assert(api_config.openrouter?)
        refute(api_config.openai?)
        refute(api_config.ruby_llm?)
      end

      def test_ruby_llm_predicate
        config = { "api_provider" => "ruby_llm" }
        api_config = ApiConfiguration.new(config)

        assert(api_config.ruby_llm?)
        refute(api_config.openai?)
        refute(api_config.openrouter?)
      end

      def test_effective_token_returns_config_token_when_present
        config = { "api_token" => "config-token", "api_provider" => "openai" }
        ENV["OPENAI_API_KEY"] = "env-token"

        api_config = ApiConfiguration.new(config)
        assert_equal("config-token", api_config.effective_token)
      end

      def test_effective_token_returns_openai_env_when_no_config_token
        config = { "api_provider" => "openai" }
        ENV["OPENAI_API_KEY"] = "env-openai-token"

        api_config = ApiConfiguration.new(config)
        assert_equal("env-openai-token", api_config.effective_token)
      end

      def test_effective_token_returns_openrouter_env_when_no_config_token
        config = { "api_provider" => "openrouter" }
        ENV["OPENROUTER_API_KEY"] = "env-openrouter-token"

        api_config = ApiConfiguration.new(config)
        assert_equal("env-openrouter-token", api_config.effective_token)
      end

      def test_effective_token_returns_ruby_llm_env_when_no_config_token
        config = { "api_provider" => "ruby_llm" }
        ENV["RUBY_LLM_API_KEY"] = "env-ruby-llm-token"

        api_config = ApiConfiguration.new(config)
        assert_equal("env-ruby-llm-token", api_config.effective_token)
      end

      def test_effective_token_falls_back_to_openai_for_ruby_llm
        config = { "api_provider" => "ruby_llm" }
        ENV["RUBY_LLM_API_KEY"] = nil
        ENV["OPENAI_API_KEY"] = "env-openai-token"
        ENV["ANTHROPIC_API_KEY"] = "env-anthropic-token"

        api_config = ApiConfiguration.new(config)
        assert_equal("env-openai-token", api_config.effective_token)
      end

      def test_effective_token_falls_back_to_anthropic_for_ruby_llm
        config = { "api_provider" => "ruby_llm" }
        ENV["RUBY_LLM_API_KEY"] = nil
        ENV["OPENAI_API_KEY"] = nil
        ENV["ANTHROPIC_API_KEY"] = "env-anthropic-token"

        api_config = ApiConfiguration.new(config)
        assert_equal("env-anthropic-token", api_config.effective_token)
      end

      def test_effective_token_returns_nil_when_no_tokens_available
        config = { "api_provider" => "openai" }
        ENV["OPENAI_API_KEY"] = nil

        api_config = ApiConfiguration.new(config)
        assert_nil(api_config.effective_token)
      end

      def test_delegates_provider_detection_to_factory
        config = { "api_provider" => "custom" }
        Roast::Factories::ApiProviderFactory.expects(:from_config).with(config).returns(:custom)

        api_config = ApiConfiguration.new(config)
        assert_equal(:custom, api_config.api_provider)
      end
    end
  end
end
