# frozen_string_literal: true

require "test_helper"

module Roast
  module Adapters
    class RubyLlmClientWrapperTest < ActiveSupport::TestCase
      def setup
        @client = RubyLlmClientWrapper.new
      end

      def test_initializes_with_nil_access_token
        assert_nil(@client.access_token)
      end

      def test_provides_models_interface
        assert_respond_to(@client, :models)
        assert_instance_of(RubyLlmClientWrapper::ModelsList, @client.models)
      end

      def test_models_list_responds_to_list
        models_list = @client.models
        assert_respond_to(models_list, :list)
        assert_equal([], models_list.list)
      end

      def test_chat_method_exists
        assert_respond_to(@client, :chat)
      end

      def test_completions_method_exists
        assert_respond_to(@client, :completions)
        completions_handler = @client.completions
        assert_respond_to(completions_handler, :complete)
      end

      def test_convert_messages_handles_hash_messages
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there" },
        ]

        converted = @client.send(:convert_messages, messages)
        assert_equal(messages, converted)
      end

      def test_convert_messages_handles_string_messages
        messages = ["Hello", "How are you?"]

        converted = @client.send(:convert_messages, messages)
        expected = [
          { role: "user", content: "Hello" },
          { role: "user", content: "How are you?" },
        ]
        assert_equal(expected, converted)
      end

      def test_convert_response_creates_proper_format
        response = "This is a test response"

        converted = @client.send(:convert_response, response)

        assert_equal("chat.completion", converted["object"])
        assert_equal(1, converted["choices"].length)
        assert_equal("assistant", converted["choices"][0]["message"]["role"])
        assert_equal(response, converted["choices"][0]["message"]["content"])
        assert_equal("stop", converted["choices"][0]["finish_reason"])
        assert_equal(0, converted["usage"]["prompt_tokens"])
        assert_equal(0, converted["usage"]["completion_tokens"])
        assert_equal(0, converted["usage"]["total_tokens"])
      end

      def test_convert_response_generates_unique_ids
        response1 = @client.send(:convert_response, "Response 1")
        response2 = @client.send(:convert_response, "Response 2")

        refute_equal(response1["id"], response2["id"])
      end

      def test_convert_response_includes_timestamp
        response = @client.send(:convert_response, "Test")

        assert(response["created"] > 0)
        assert(response["created"] <= Time.now.to_i)
      end
    end
  end
end
