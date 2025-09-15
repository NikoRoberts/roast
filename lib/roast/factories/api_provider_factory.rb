# typed: true
# frozen_string_literal: true

module Roast
  module Factories
    # Factory for determining and creating API provider configurations
    class ApiProviderFactory
      SUPPORTED_PROVIDERS = {
        "openai" => :openai,
        "openrouter" => :openrouter,
        "ruby_llm" => :ruby_llm,
      }.freeze

      DEFAULT_PROVIDER = :openai

      class << self
        # Determines the API provider from configuration
        # @param config [Hash] The configuration hash
        # @return [Symbol] The API provider symbol (:openai or :openrouter)
        def from_config(config)
          return DEFAULT_PROVIDER unless config["api_provider"]

          provider_name = config["api_provider"].to_s.downcase
          provider = SUPPORTED_PROVIDERS[provider_name]

          unless provider
            Roast::Helpers::Logger.warn("Unknown API provider '#{provider_name}', defaulting to #{DEFAULT_PROVIDER}")
            return DEFAULT_PROVIDER
          end

          provider
        end

        # Returns true if the provider is OpenRouter
        # @param provider [Symbol] The provider symbol
        # @return [Boolean]
        def openrouter?(provider)
          provider == :openrouter
        end

        # Returns true if the provider is OpenAI
        # @param provider [Symbol] The provider symbol
        # @return [Boolean]
        def openai?(provider)
          provider == :openai
        end

        # Returns true if the provider is RubyLLM
        # @param provider [Symbol] The provider symbol
        # @return [Boolean]
        def ruby_llm?(provider)
          provider == :ruby_llm
        end

        # Returns the list of supported provider names
        # @return [Array<String>]
        def supported_provider_names
          SUPPORTED_PROVIDERS.keys
        end

        # Validates a provider symbol
        # @param provider [Symbol] The provider to validate
        # @return [Boolean]
        def valid_provider?(provider)
          SUPPORTED_PROVIDERS.values.include?(provider)
        end
      end
    end
  end
end
