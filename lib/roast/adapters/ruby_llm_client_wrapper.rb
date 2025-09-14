# typed: true
# frozen_string_literal: true

begin
  require "ruby_llm"
rescue LoadError
  # RubyLLM will be required when needed
end

module Roast
  module Adapters
    # Wrapper class that adapts RubyLLM to work with Raix's client interface
    class RubyLLMClientWrapper
      attr_reader :access_token

      def initialize
        @access_token = nil
      end

      # Implement the models interface expected by Raix
      def models
        ModelsList.new
      end

      # Chat completion interface for Raix
      def chat(parameters:)
        unless defined?(RubyLLM)
          raise NameError, "RubyLLM constant is not defined. Make sure the ruby_llm gem is installed and required."
        end

        # Extract messages and model from parameters
        messages = parameters[:messages] || []
        model = parameters[:model]

        # Convert Raix message format to RubyLLM format
        ruby_llm_messages = convert_messages(messages)

        # Create RubyLLM chat instance
        chat = RubyLLM.chat

        # Set model if specified
        chat.model = model if model

        # Make the request using RubyLLM
        response = chat.ask(ruby_llm_messages.last[:content])

        # Convert response to Raix expected format
        convert_response(response)
      end

      private

      # Convert Raix message format to RubyLLM format
      def convert_messages(messages)
        messages.map do |message|
          case message
          when Hash
            message
          when String
            { role: "user", content: message }
          else
            { role: "user", content: message.to_s }
          end
        end
      end

      # Convert RubyLLM response to Raix expected format
      def convert_response(response)
        timestamp = Time.now.to_f
        {
          "id" => "ruby_llm_#{(timestamp * 1_000_000).to_i}_#{rand(1000)}",
          "object" => "chat.completion",
          "created" => timestamp.to_i,
          "model" => "ruby_llm",
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "content" => response.to_s,
              },
              "finish_reason" => "stop",
            },
          ],
          "usage" => {
            "prompt_tokens" => 0,
            "completion_tokens" => 0,
            "total_tokens" => 0,
          },
        }
      end

      # Mock models list for validation
      class ModelsList
        def list
          []
        end
      end
    end
  end
end
