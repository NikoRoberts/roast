# typed: false
# frozen_string_literal: true

module Roast
  module Workflow
    class BaseWorkflow
      include Raix::ChatCompletion

      attr_accessor :file,
        :concise,
        :output_file,
        :pause_step_name,
        :verbose,
        :name,
        :context_path,
        :resource,
        :session_name,
        :session_timestamp,
        :model,
        :workflow_configuration,
        :storage_type,
        :context_management_config

      attr_reader :pre_processing_data, :context_manager

      delegate :api_provider, :openai?, to: :workflow_configuration, allow_nil: true
      delegate :output, :output=, :append_to_final_output, :final_output, to: :output_manager
      delegate :metadata, :metadata=, to: :metadata_manager
      delegate_missing_to :output

      def initialize(file = nil, name: nil, context_path: nil, resource: nil, session_name: nil, workflow_configuration: nil, pre_processing_data: nil)
        @file = file
        @name = name || self.class.name.underscore.split("/").last
        @context_path = context_path || ContextPathResolver.resolve(self.class)
        @resource = resource || Roast::Resources.for(file)
        @session_name = session_name || @name
        @session_timestamp = nil
        @workflow_configuration = workflow_configuration
        @pre_processing_data = pre_processing_data ? DotAccessHash.new(pre_processing_data).freeze : nil

        # Initialize managers
        @output_manager = OutputManager.new
        @metadata_manager = MetadataManager.new
        @context_manager = ContextManager.new
        @context_management_config = {}

        # Setup prompt and handlers
        read_sidecar_prompt.then do |prompt|
          next unless prompt

          transcript << { system: prompt }
        end
        Roast::Tools.setup_interrupt_handler(transcript)
        Roast::Tools.setup_exit_handler(self)
      end

      # Override chat_completion to add instrumentation
      def chat_completion(**kwargs)
        start_time = Time.now
        step_model = kwargs[:model]

        with_model(step_model) do
          # Configure context manager if needed
          if @context_management_config.any?
            @context_manager.configure(@context_management_config)
          end

          # Track token usage before API call
          messages = kwargs[:messages] || transcript.flatten.compact
          if @context_management_config[:enabled]
            @context_manager.track_usage(messages)
            @context_manager.check_warnings
          end

          ActiveSupport::Notifications.instrument("roast.chat_completion.start", {
            model: model,
            parameters: kwargs.except(:openai, :model),
          })

          # Clear any previous response
          Thread.current[:chat_completion_response] = nil

          # Handle RubyLLM provider directly, bypass Raix
          result = if workflow_configuration&.ruby_llm?
            handle_ruby_llm_completion(**kwargs)
          else
            # Call the parent module's chat_completion
            # skip model because it is read directly from the model method
            super(**kwargs.except(:model))
          end
          execution_time = Time.now - start_time

          # Extract token usage from the raw response stored by Raix
          raw_response = Thread.current[:chat_completion_response]
          token_usage = extract_token_usage(raw_response) if raw_response

          # Update context manager with actual token usage if available
          if token_usage && @context_management_config[:enabled]
            actual_total = token_usage.dig("total_tokens") || token_usage.dig(:total_tokens)
            @context_manager.update_with_actual_usage(actual_total) if actual_total
          end

          ActiveSupport::Notifications.instrument("roast.chat_completion.complete", {
            success: true,
            model: model,
            parameters: kwargs.except(:openai, :model),
            execution_time: execution_time,
            response_size: result.to_s.length,
            token_usage: token_usage,
          })
          result
        end
      rescue Faraday::ResourceNotFound => e
        execution_time = Time.now - start_time
        message = e.response.dig(:body, "error", "message") || e.message
        error = Roast::Errors::ResourceNotFoundError.new(message)
        error.set_backtrace(e.backtrace)
        log_and_raise_error(error, message, step_model || model, kwargs, execution_time)
      rescue => e
        execution_time = Time.now - start_time
        log_and_raise_error(e, e.message, step_model || model, kwargs, execution_time)
      end

      def with_model(model)
        previous_model = @model
        @model = model
        yield
      ensure
        @model = previous_model
      end

      def workflow
        self
      end

      # Expose output and metadata managers for state management
      attr_reader :output_manager, :metadata_manager

      private

      def log_and_raise_error(error, message, model, params, execution_time)
        ActiveSupport::Notifications.instrument("roast.chat_completion.error", {
          error: error.class.name,
          message: message,
          model: model,
          parameters: params.except(:openai, :model),
          execution_time: execution_time,
        })

        raise error
      end

      def read_sidecar_prompt
        Roast::Helpers::PromptLoader.load_prompt(self, file)
      end

      def extract_token_usage(result)
        # Token usage is typically in the response metadata
        # This depends on the API provider's response format
        return unless result.is_a?(Hash) || result.respond_to?(:to_h)

        result_hash = result.is_a?(Hash) ? result : result.to_h
        result_hash.dig("usage") || result_hash.dig(:usage)
      end

      # Handle RubyLLM completions directly without going through Raix
      def handle_ruby_llm_completion(**kwargs)
        require "ruby_llm"

        messages = kwargs[:messages] || transcript.flatten.compact
        model_name = kwargs[:model] || model

        $stderr.puts "🚀 Direct RubyLLM completion - Model: #{model_name}"
        $stderr.puts "🚀 Messages count: #{messages.length}"

        # Ensure RubyLLM has the right configuration before creating chat instance
        configure_ruby_llm_for_model(model_name)

        # Create RubyLLM chat instance with model
        chat = if model_name
          RubyLLM.chat(model: model_name)
        else
          RubyLLM.chat
        end

        # Extract the content from the last user message
        last_message = messages.last
        content = case last_message
        when Hash
          last_message[:content] || last_message["content"]
        when String
          last_message
        else
          last_message.to_s
        end

        $stderr.puts "🚀 Making RubyLLM request with content: #{content[0...100]}..."
        response_text = chat.ask(content)
        $stderr.puts "✅ RubyLLM request completed successfully"

        # Return response in the format Roast expects
        response_text
      rescue => e
        $stderr.puts "❌ RubyLLM error: #{e.message}"
        raise e
      end

      # Configure RubyLLM for the specific model at runtime
      def configure_ruby_llm_for_model(model_name)
        return unless model_name

        # Get API token from workflow configuration
        api_token = workflow_configuration&.api_token
        return unless api_token

        $stderr.puts "🔧 Configuring RubyLLM for model: #{model_name}"

        # Set environment variables - RubyLLM reads from ENV vars
        if model_name.include?("gemini")
          ENV['GEMINI_API_KEY'] = api_token.strip
          $stderr.puts "🔧 Set GEMINI_API_KEY environment variable for Gemini model"

          # Also set these if they exist in the environment
          if ENV['GOOGLE_CLOUD_PROJECT']
            $stderr.puts "🔧 Using existing GOOGLE_CLOUD_PROJECT: #{ENV['GOOGLE_CLOUD_PROJECT']}"
          end
          if ENV['GOOGLE_CLOUD_LOCATION']
            $stderr.puts "🔧 Using existing GOOGLE_CLOUD_LOCATION: #{ENV['GOOGLE_CLOUD_LOCATION']}"
          end
        elsif model_name.include?("claude") && !model_name.include?("anthropic.")
          ENV['ANTHROPIC_API_KEY'] = api_token.strip
          $stderr.puts "🔧 Set ANTHROPIC_API_KEY environment variable for Claude model"
        elsif model_name.start_with?("anthropic.", "amazon.", "ai21.", "cohere.", "meta.", "mistral.")
          # Bedrock models - configure AWS
          configure_aws_for_bedrock(api_token)
        else
          # Default to OpenAI
          ENV['OPENAI_API_KEY'] = api_token.strip
          $stderr.puts "🔧 Set OPENAI_API_KEY environment variable for OpenAI model"
        end
      end

      # Configure AWS credentials for Bedrock at runtime
      def configure_aws_for_bedrock(config_value)
        $stderr.puts "🔧 Configuring AWS for Bedrock"

        begin
          if config_value.start_with?("{")
            aws_config = JSON.parse(config_value)
            ENV['AWS_REGION'] = aws_config['region'] if aws_config['region']
            ENV['AWS_ACCESS_KEY_ID'] = aws_config['access_key'] if aws_config['access_key']
            ENV['AWS_SECRET_ACCESS_KEY'] = aws_config['secret_key'] if aws_config['secret_key']
          else
            ENV['AWS_REGION'] = config_value
          end
          $stderr.puts "🔧 AWS configuration set for Bedrock"
        rescue JSON::ParserError
          ENV['AWS_REGION'] = config_value
        end
      end
    end
  end
end
