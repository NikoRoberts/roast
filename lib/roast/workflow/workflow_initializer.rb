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
          if Raix.configuration.openai_client.nil?
            warn_about_missing_raix_configuration(:ruby_llm)
          end
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
        when :openai, :ruby_llm
          Raix.configuration.openai_client.present?
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
            # Try to determine which provider based on common key patterns
            # or use the first available API key
            config.openai_api_key = @configuration.api_token.strip if @configuration.api_token
            $stderr.puts "🔧 Configured RubyLLM with API token"
          else
            $stderr.puts "⚠️  No API token found for RubyLLM configuration"
          end
        end

        # Create a client wrapper that works with Raix
        # Since Raix doesn't have native ruby_llm_client support,
        # we'll use the openai_client slot for our wrapper
        require_relative "../adapters/ruby_llm_client_wrapper"
        client = Roast::Adapters::RubyLLMClientWrapper.new
        $stderr.puts "🔧 Created RubyLLMClientWrapper instance: #{client.class}"

        Raix.configure do |config|
          config.openai_client = client
        end
        $stderr.puts "✅ Configured Raix with RubyLLM wrapper as openai_client"
        $stderr.puts "🔧 Current Raix openai_client: #{Raix.configuration.openai_client.class}"

        client
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
    end
  end
end
