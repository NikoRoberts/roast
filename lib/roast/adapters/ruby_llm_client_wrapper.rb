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
    class RubyLlmClientWrapper
      attr_reader :access_token

      def initialize
        @access_token = nil
      end

      # Implement the models interface expected by Raix
      def models
        ModelsList.new
      end

      # Implement completions interface that Raix might use
      def completions
        CompletionsHandler.new(self)
      end

      # Chat completion interface for Raix
      def chat(parameters:)
        $stderr.puts "🚀 RubyLlmClientWrapper.chat called with parameters: #{parameters.keys.join(', ')}"
        $stderr.puts "🚀 Model requested: #{parameters[:model]}"
        $stderr.puts "🚀 Messages count: #{(parameters[:messages] || []).length}"

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
        $stderr.puts "🚀 Created RubyLLM chat instance: #{chat.class}"

        # Set model if specified
        if model
          chat.model = model
          $stderr.puts "🚀 Set model to: #{model}"
        end

        # Make the request using RubyLLM
        $stderr.puts "🚀 Making RubyLLM request with content: #{ruby_llm_messages.last[:content][0...100]}..."
        response = chat.ask(ruby_llm_messages.last[:content])
        $stderr.puts "🚀 Received response: #{response.to_s[0...100]}..."

        # Convert response to Raix expected format
        result = convert_response(response)
        $stderr.puts "✅ RubyLLM request completed successfully"
        result
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

      # Handler for completions API that delegates back to chat
      class CompletionsHandler
        def initialize(client)
          @client = client
        end

        def complete(parameters)
          $stderr.puts "🚀 CompletionsHandler.complete called with: #{parameters.keys.join(', ')}"
          # Delegate to the chat method with proper parameter mapping
          @client.chat(parameters: parameters)
        end
      end
    end
  end
end
