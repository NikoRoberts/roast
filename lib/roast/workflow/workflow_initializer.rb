# typed: false
# frozen_string_literal: true

module Roast
  module Workflow
    # Handles initialization of workflow dependencies: initializers, tools, and API clients
    class WorkflowInitializer
      def initialize(configuration)
        @configuration = configuration
      end

      def setup
        load_roast_initializers
        check_raix_configuration
        include_tools
        configure_api_client
      end

      private

      def load_roast_initializers
        Roast::Initializers.load_all
      end

      def check_raix_configuration
        # Skip check in test environment
        return if ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test" || defined?(Minitest)

        # Only check if the workflow has steps that would need API access
        return if @configuration.steps.empty?

        # Strip whitespace from existing Raix clients
        strip_tokens_from_existing_clients

        # Check if Raix has been configured with the appropriate client
        case @configuration.api_provider
        when :openai
          if Raix.configuration.openai_client.nil?
            warn_about_missing_raix_configuration(:openai)
          end
        when :openrouter
          if Raix.configuration.openrouter_client.nil?
            warn_about_missing_raix_configuration(:openrouter)
          end
        when :ruby_llm
          # RubyLLM integration bypasses Raix entirely, no configuration check needed
        when nil
          # If no api_provider is set but we have steps that might need API access,
          # check if any client is configured
          if Raix.configuration.openai_client.nil? && Raix.configuration.openrouter_client.nil?
            warn_about_missing_raix_configuration(:any)
          end
        end
      end

      def warn_about_missing_raix_configuration(provider)
        ::CLI::UI.frame_style = :box
        ::CLI::UI::Frame.open("{{red:Raix Configuration Missing}}", color: :red) do
          case provider
          when :openai
            puts ::CLI::UI.fmt("{{yellow:⚠️  Warning: Raix OpenAI client is not configured!}}")
          when :openrouter
            puts ::CLI::UI.fmt("{{yellow:⚠️  Warning: Raix OpenRouter client is not configured!}}")
          when :ruby_llm
            puts ::CLI::UI.fmt("{{yellow:⚠️  Warning: Raix RubyLLM client is not configured!}}")
          else
            puts ::CLI::UI.fmt("{{yellow:⚠️  Warning: Raix is not configured!}}")
          end
          puts
          puts "Roast requires Raix to be properly initialized to make API calls."
          puts ::CLI::UI.fmt("To fix this, create a file at {{cyan:.roast/initializers/raix.rb}} with:")
          puts
          puts ::CLI::UI.fmt("{{cyan:# frozen_string_literal: true}}")
          puts
          puts ::CLI::UI.fmt("{{cyan:require \"raix\"}}")

          if provider == :openrouter
            puts ::CLI::UI.fmt("{{cyan:require \"open_router\"}}")
            puts
            puts ::CLI::UI.fmt("{{cyan:Raix.configure do |config|}}")
            puts ::CLI::UI.fmt("{{cyan:  config.openrouter_client = OpenRouter::Client.new(}}")
            puts ::CLI::UI.fmt("{{cyan:    access_token: ENV.fetch(\"OPENROUTER_API_KEY\"),}}")
            puts ::CLI::UI.fmt("{{cyan:    uri_base: \"https://openrouter.ai/api/v1\",}}")
            puts ::CLI::UI.fmt("{{cyan:  )}}")
          elsif provider == :ruby_llm
            puts ::CLI::UI.fmt("{{cyan:require \"ruby_llm\"}}")
            puts
            puts ::CLI::UI.fmt("{{cyan:Raix.configure do |config|}}")
            puts ::CLI::UI.fmt("{{cyan:  config.ruby_llm_client = RubyLLM}}")
            puts ::CLI::UI.fmt("{{cyan:end}}")
            puts
            puts ::CLI::UI.fmt("{{cyan:# Configure RubyLLM with your preferred provider:}}")
            puts ::CLI::UI.fmt("{{cyan:RubyLLM.configure do |config|}}")
            puts ::CLI::UI.fmt("{{cyan:  # Example for OpenAI:}}")
            puts ::CLI::UI.fmt("{{cyan:  config.openai_api_key = ENV.fetch(\"OPENAI_API_KEY\")}}")
            puts ::CLI::UI.fmt("{{cyan:  # Or Anthropic:}}")
            puts ::CLI::UI.fmt("{{cyan:  # config.anthropic_api_key = ENV.fetch(\"ANTHROPIC_API_KEY\")}}")
            puts ::CLI::UI.fmt("{{cyan:  # Or any other supported provider}}")
          else
            puts
            puts ::CLI::UI.fmt("{{cyan:faraday_retry = false}}")
            puts ::CLI::UI.fmt("{{cyan:begin}}")
            puts ::CLI::UI.fmt("{{cyan:  require \"faraday/retry\"}}")
            puts ::CLI::UI.fmt("{{cyan:  faraday_retry = true}}")
            puts ::CLI::UI.fmt("{{cyan:rescue LoadError}}")
            puts ::CLI::UI.fmt("{{cyan:  # Do nothing}}")
            puts ::CLI::UI.fmt("{{cyan:end}}")
            puts
            puts ::CLI::UI.fmt("{{cyan:Raix.configure do |config|}}")
            puts ::CLI::UI.fmt("{{cyan:  config.openai_client = OpenAI::Client.new(}}")
            puts ::CLI::UI.fmt("{{cyan:    access_token: ENV.fetch(\"OPENAI_API_KEY\"),}}")
            puts ::CLI::UI.fmt("{{cyan:    uri_base: \"https://api.openai.com/v1\",}}")
            puts ::CLI::UI.fmt("{{cyan:  ) do |f|}}")
            puts ::CLI::UI.fmt("{{cyan:    if faraday_retry}}")
            puts ::CLI::UI.fmt("{{cyan:      f.request(:retry, {}}")
            puts ::CLI::UI.fmt("{{cyan:        max: 2,}}")
            puts ::CLI::UI.fmt("{{cyan:        interval: 0.05,}}")
            puts ::CLI::UI.fmt("{{cyan:        interval_randomness: 0.5,}}")
            puts ::CLI::UI.fmt("{{cyan:        backoff_factor: 2,}}")
            puts ::CLI::UI.fmt("{{cyan:      })}}")
            puts ::CLI::UI.fmt("{{cyan:    end}}")
            puts ::CLI::UI.fmt("{{cyan:  end}}")
          end
          puts ::CLI::UI.fmt("{{cyan:end}}")
          puts
          puts "For Shopify users, you need to use the LLM gateway proxy instead."
          puts "Check the #roast slack channel for more information."
          puts
        end
        raise ::CLI::Kit::Abort, "Please configure Raix before running workflows."
      end

      def include_tools
        return unless @configuration.tools.present? || @configuration.mcp_tools.present?

        # Only include modules if they haven't been included already to avoid method redefinition warnings
        BaseWorkflow.include(Raix::FunctionDispatch) unless BaseWorkflow.included_modules.include?(Raix::FunctionDispatch)
        BaseWorkflow.include(Roast::Helpers::FunctionCachingInterceptor) unless BaseWorkflow.included_modules.include?(Roast::Helpers::FunctionCachingInterceptor)

        if @configuration.tools.present?
          @configuration.tools.map(&:constantize).each do |tool|
            BaseWorkflow.include(tool) unless BaseWorkflow.included_modules.include?(tool)
          end
        end

        if @configuration.mcp_tools.present?
          BaseWorkflow.include(Raix::MCP) unless BaseWorkflow.included_modules.include?(Raix::MCP)

          # Create an interpolator for MCP tool configuration
          # We use Object.new as the context because this interpolation happens during
          # initialization, before any workflow instance exists. Since we don't have
          # a workflow instance yet, we use a minimal object that can still evaluate
          # Ruby expressions like ENV['HOME'] or any other valid Ruby code.
          interpolator = Interpolator.new(Object.new)

          @configuration.mcp_tools.each do |tool|
            # Interpolate the config values
            config = interpolate_config(tool.config, interpolator)

            # Create the appropriate client based on config
            client = if config["url"]
              Raix::MCP::SseClient.new(
                config["url"],
                headers: config["env"] || {},
              )
            elsif config["command"]
              args = [config["command"]]
              args += config["args"] if config["args"]
              Raix::MCP::StdioClient.new(*args, config["env"] || {})
            end

            BaseWorkflow.mcp(client: client, only: tool.only, except: tool.except)
          end
        end

        post_configure_tools
      end

      def post_configure_tools
        @configuration.tools.each do |tool_name|
          tool_module = tool_name.constantize

          if tool_module.respond_to?(:post_configuration_setup)
            tool_config = @configuration.tool_config(tool_name)
            tool_module.post_configuration_setup(BaseWorkflow, tool_config)
          end
        end
      end

      def configure_api_client
        $stderr.puts "🔧 Starting API client configuration..."
        $stderr.puts "🔧 API provider: #{@configuration.api_provider.inspect}"
        $stderr.puts "🔧 Has API token: #{!@configuration.api_token.blank?}"
        $stderr.puts "🔧 Client already configured: #{api_client_already_configured?}"

        # Skip if api client is already configured (e.g., by initializers)
        if api_client_already_configured?
          $stderr.puts "✅ API client already configured, skipping"
          return
        end

        # Skip if no api_token is provided in the workflow
        if @configuration.api_token.blank?
          $stderr.puts "⚠️  No API token provided, skipping client configuration"
          return
        end

        client = case @configuration.api_provider
        when :openrouter
          $stderr.puts "🔧 Configuring OpenRouter client..."
          configure_openrouter_client
        when :openai
          $stderr.puts "🔧 Configuring OpenAI client..."
          configure_openai_client
        when :ruby_llm
          $stderr.puts "🔧 Configuring RubyLLM client..."
          configure_ruby_llm_client
        when nil
          # Skip configuration if no api_provider is set
          $stderr.puts "⚠️  No api_provider set, skipping configuration"
          return
        else
          raise "Unsupported api_provider in workflow configuration: #{@configuration.api_provider}"
        end

        # Validate the client configuration by making a test API call
        if client
          $stderr.puts "🔧 Validating client configuration..."
          validate_api_client(client)
          $stderr.puts "✅ Client configuration complete"
        end
      rescue OpenRouter::ConfigurationError, Faraday::UnauthorizedError => e
        error = Roast::Errors::AuthenticationError.new("API authentication failed: No API token provided or token is invalid")
        error.set_backtrace(e.backtrace)

        ActiveSupport::Notifications.instrument("roast.workflow.start.error", {
          error: error.class.name,
          message: error.message,
        })

        raise error
      rescue => e
        Roast::Helpers::Logger.error("Error configuring API client: #{e.message}")
        raise e
      end

      def api_client_already_configured?
        case @configuration.api_provider
        when :openrouter
          Raix.configuration.openrouter_client.present?
        when :openai
          Raix.configuration.openai_client.present?
        when :ruby_llm
          # RubyLLM doesn't need Raix client configuration
          false
        else
          false
        end
      end

      def client_options
        {
          access_token: @configuration.api_token&.strip,
          uri_base: @configuration.uri_base&.to_s,
        }.compact
      end

      def configure_openrouter_client
        $stderr.puts "Configuring OpenRouter client with token from workflow"
        require "open_router"

        client = OpenRouter::Client.new(client_options)

        Raix.configure do |config|
          config.openrouter_client = client
        end
        client
      end

      def configure_openai_client
        $stderr.puts "Configuring OpenAI client with token from workflow"
        require "openai"

        client = OpenAI::Client.new(client_options)

        Raix.configure do |config|
          config.openai_client = client
        end
        client
      end

      def configure_ruby_llm_client
        $stderr.puts "🔧 Configuring RubyLLM client with token from workflow"
        $stderr.puts "🔧 API provider: #{@configuration.api_provider}"
        $stderr.puts "🔧 Has API token: #{!@configuration.api_token.nil?}"

        begin
          require "ruby_llm"
          $stderr.puts "✅ RubyLLM gem loaded successfully"
        rescue LoadError
          raise ::CLI::Kit::Abort, "RubyLLM gem is required but not available. Please add 'gem \"ruby_llm\"' to your Gemfile."
        end

        # Configure RubyLLM based on the provider or API key available
        RubyLLM.configure do |config|
          if @configuration.api_token
            # RubyLLM uses environment variables for different providers
            # We'll set the appropriate ENV var based on the model
            model = @configuration.model
            api_token = @configuration.api_token.strip

            if model&.include?("gemini")
              ENV['GEMINI_API_KEY'] = api_token
              $stderr.puts "🔧 Set GEMINI_API_KEY environment variable for Gemini model"
            elsif model&.include?("claude") && !model.include?("anthropic.")
              # Direct Claude API (not Bedrock)
              ENV['ANTHROPIC_API_KEY'] = api_token
              $stderr.puts "🔧 Set ANTHROPIC_API_KEY environment variable for Claude model"
            elsif is_bedrock_model?(model)
              # AWS Bedrock models - api_token should contain AWS credentials or region
              configure_bedrock_env(api_token)
              $stderr.puts "🔧 Configured AWS Bedrock environment variables"
            elsif is_other_provider_model?(model)
              configure_other_provider_env(model, api_token)
            else
              # Default to OpenAI for other models
              ENV['OPENAI_API_KEY'] = api_token
              $stderr.puts "🔧 Set OPENAI_API_KEY environment variable for OpenAI model"
            end
          else
            $stderr.puts "⚠️  No API token found for RubyLLM configuration"
          end
        end

        # For RubyLLM, we don't need to configure Raix since we handle it directly in BaseWorkflow
        $stderr.puts "✅ RubyLLM configured for direct integration (bypassing Raix)"

        # Return a simple marker object to indicate success
        :ruby_llm_configured
      end

      def validate_api_client(client)
        # Make a lightweight API call to validate the token
        client.models.list if client.respond_to?(:models)
      end

      def interpolate_config(config, interpolator)
        interpolated = {}
        config.each do |key, value|
          interpolated[key] = case value
          when String
            interpolator.interpolate(value)
          when Array
            value.map { |v| v.is_a?(String) ? interpolator.interpolate(v) : v }
          when Hash
            interpolate_config(value, interpolator)
          else
            value
          end
        end
        interpolated
      end

      def strip_tokens_from_existing_clients
        strip_token_in_client(Raix.configuration.openai_client)
        strip_token_in_client(Raix.configuration.openrouter_client)
      end

      def strip_token_in_client(client)
        return unless client.respond_to?(:access_token)

        client.instance_variable_set(:@access_token, client.access_token&.strip)
      end

      # Check if the model is an AWS Bedrock model
      def is_bedrock_model?(model)
        return false unless model

        bedrock_prefixes = [
          "anthropic.",     # anthropic.claude-3-sonnet-20240229-v1:0
          "amazon.",        # amazon.titan-text-express-v1
          "ai21.",          # ai21.j2-ultra-v1
          "cohere.",        # cohere.command-text-v14
          "meta.",          # meta.llama2-70b-chat-v1
          "mistral.",       # mistral.mistral-7b-instruct-v0:2
          "stability.",     # stability.stable-diffusion-xl-base-1-0
        ]

        bedrock_prefixes.any? { |prefix| model.start_with?(prefix) }
      end

      # Configure AWS Bedrock environment variables
      def configure_bedrock_env(config_value)
        # config_value could be:
        # 1. Just AWS region: "us-east-1"
        # 2. JSON with AWS credentials: '{"region":"us-east-1","access_key":"..","secret_key":".."}'
        # 3. AWS profile name: "default" or "production"

        begin
          # Try parsing as JSON first
          if config_value.start_with?("{")
            aws_config = JSON.parse(config_value)
            ENV['AWS_REGION'] = aws_config['region'] if aws_config['region']
            ENV['AWS_ACCESS_KEY_ID'] = aws_config['access_key'] if aws_config['access_key']
            ENV['AWS_SECRET_ACCESS_KEY'] = aws_config['secret_key'] if aws_config['secret_key']
            ENV['AWS_PROFILE'] = aws_config['profile'] if aws_config['profile']
            $stderr.puts "🔧 Set AWS credentials from JSON config"
          elsif config_value.match?(/^[a-z0-9-]+$/)
            # Looks like a region or profile name
            if config_value.include?("-")
              # Probably a region like "us-east-1"
              ENV['AWS_REGION'] = config_value
              $stderr.puts "🔧 Set AWS_REGION to #{config_value}"
            else
              # Probably a profile name
              ENV['AWS_PROFILE'] = config_value
              $stderr.puts "🔧 Set AWS_PROFILE to #{config_value}"
            end
          else
            # Treat as region by default
            ENV['AWS_REGION'] = config_value
            $stderr.puts "🔧 Set AWS_REGION to #{config_value}"
          end
        rescue JSON::ParserError
          # If JSON parsing fails, treat as region/profile
          ENV['AWS_REGION'] = config_value
          $stderr.puts "🔧 Set AWS_REGION to #{config_value} (fallback)"
        end
      end

      # Check if model belongs to other supported providers
      def is_other_provider_model?(model)
        return false unless model

        other_provider_patterns = [
          /mistral/i,           # Mistral models
          /deepseek/i,          # DeepSeek models
          /perplexity/i,        # Perplexity models
          /llama.*ollama/i,     # Ollama models
        ]

        other_provider_patterns.any? { |pattern| model.match?(pattern) }
      end

      # Configure environment variables for other supported providers
      def configure_other_provider_env(model, api_token)
        case model.downcase
        when /mistral/
          ENV['MISTRAL_API_KEY'] = api_token
          $stderr.puts "🔧 Set MISTRAL_API_KEY environment variable for Mistral model"
        when /deepseek/
          ENV['DEEPSEEK_API_KEY'] = api_token
          $stderr.puts "🔧 Set DEEPSEEK_API_KEY environment variable for DeepSeek model"
        when /perplexity/
          ENV['PERPLEXITY_API_KEY'] = api_token
          $stderr.puts "🔧 Set PERPLEXITY_API_KEY environment variable for Perplexity model"
        when /ollama/
          # Ollama typically doesn't need API key, but may need base URL
          ENV['OLLAMA_API_BASE'] = api_token
          $stderr.puts "🔧 Set OLLAMA_API_BASE environment variable for Ollama model"
        else
          # If we can't determine the provider, default to OpenAI
          ENV['OPENAI_API_KEY'] = api_token
          $stderr.puts "🔧 Set OPENAI_API_KEY environment variable (unknown provider fallback)"
        end
      end
    end
  end
end
