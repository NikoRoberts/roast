# frozen_string_literal: true

require "test_helper"

module Roast
  module Factories
    class ApiProviderFactoryTest < ActiveSupport::TestCase
      def test_from_config_with_openai
        config = { "api_provider" => "openai" }
        assert_equal(:openai, ApiProviderFactory.from_config(config))
      end

      def test_from_config_with_openrouter
        config = { "api_provider" => "openrouter" }
        assert_equal(:openrouter, ApiProviderFactory.from_config(config))
      end

      def test_from_config_with_ruby_llm
        config = { "api_provider" => "ruby_llm" }
        assert_equal(:ruby_llm, ApiProviderFactory.from_config(config))
      end

      def test_from_config_with_uppercase
        config = { "api_provider" => "OpenAI" }
        assert_equal(:openai, ApiProviderFactory.from_config(config))
      end

      def test_from_config_with_mixed_case
        config = { "api_provider" => "OpenRouter" }
        assert_equal(:openrouter, ApiProviderFactory.from_config(config))
      end

      def test_from_config_with_ruby_llm_mixed_case
        config = { "api_provider" => "Ruby_LLM" }
        assert_equal(:ruby_llm, ApiProviderFactory.from_config(config))
      end

      def test_from_config_without_api_provider
        config = {}
        assert_equal(:openai, ApiProviderFactory.from_config(config))
      end

      def test_from_config_with_nil_api_provider
        config = { "api_provider" => nil }
        assert_equal(:openai, ApiProviderFactory.from_config(config))
      end

      def test_from_config_with_unknown_provider
        config = { "api_provider" => "unknown" }

        Roast::Helpers::Logger.expects(:warn).with("Unknown API provider 'unknown', defaulting to openai")

        assert_equal(:openai, ApiProviderFactory.from_config(config))
      end

      def test_openrouter_predicate
        assert(ApiProviderFactory.openrouter?(:openrouter))
        refute(ApiProviderFactory.openrouter?(:openai))
        refute(ApiProviderFactory.openrouter?(:ruby_llm))
        refute(ApiProviderFactory.openrouter?(:unknown))
      end

      def test_openai_predicate
        assert(ApiProviderFactory.openai?(:openai))
        refute(ApiProviderFactory.openai?(:openrouter))
        refute(ApiProviderFactory.openai?(:ruby_llm))
        refute(ApiProviderFactory.openai?(:unknown))
      end

      def test_ruby_llm_predicate
        assert(ApiProviderFactory.ruby_llm?(:ruby_llm))
        refute(ApiProviderFactory.ruby_llm?(:openai))
        refute(ApiProviderFactory.ruby_llm?(:openrouter))
        refute(ApiProviderFactory.ruby_llm?(:unknown))
      end

      def test_supported_provider_names
        names = ApiProviderFactory.supported_provider_names
        assert_includes(names, "openai")
        assert_includes(names, "openrouter")
        assert_includes(names, "ruby_llm")
        assert_equal(3, names.length)
      end

      def test_valid_provider_predicate
        assert(ApiProviderFactory.valid_provider?(:openai))
        assert(ApiProviderFactory.valid_provider?(:openrouter))
        assert(ApiProviderFactory.valid_provider?(:ruby_llm))
        refute(ApiProviderFactory.valid_provider?(:unknown))
        refute(ApiProviderFactory.valid_provider?(nil))
      end

      def test_constants_are_frozen
        assert(ApiProviderFactory::SUPPORTED_PROVIDERS.frozen?)
        assert_equal(:openai, ApiProviderFactory::DEFAULT_PROVIDER)
      end
    end
  end
end
