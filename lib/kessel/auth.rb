# frozen_string_literal: true

require 'grpc'
require 'kessel/version'

module Kessel
  # OpenID Connect authentication module for Kessel services.
  #
  # This module provides OIDC Client Credentials flow authentication
  # with automatic discovery. Works seamlessly with OIDC-compliant providers.
  #
  # @example Basic usage
  #   auth = Kessel::Auth::OAuth.new(
  #     client_id: 'my-app',
  #     client_secret: 'secret',
  #     token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
  #   )
  #   token = auth.token
  #
  # @author Project Kessel
  # @since 1.0.0
  module Auth
    # Exception raised when OAuth functionality is requested but dependencies are missing.
    class OAuthDependencyError < StandardError
      # Creates a new OAuth dependency error.
      #
      # @param message [String] Error message describing the missing dependency
      def initialize(message = 'OAuth functionality requires the openid_connect gem')
        super
      end
    end

    # Exception raised when OAuth authentication fails.
    class OAuthAuthenticationError < StandardError
      # Creates a new OAuth authentication error.
      #
      # @param message [String] Error message describing the authentication failure
      def initialize(message = 'OAuth authentication failed')
        super
      end
    end

    OIDCDiscoveryMetadata = Struct.new(:token_endpoint)
    RefreshTokenResponse = Struct.new(:access_token, :expires_in)

    def fetch_oidc_discovery(provider_url)
      check_dependencies!
      discovery = ::OpenIDConnect::Discovery::Provider::Config.discover!(provider_url)
      OIDCDiscoveryMetadata.new(discovery.token_endpoint)
    rescue StandardError => e
      raise OAuthAuthenticationError, "Failed to discover OIDC configuration from #{provider_url}: #{e.message}"
    end

    # Checks if the openid_connect gem is available.
    #
    # @raise [OAuthDependencyError] if openid_connect gem is missing
    # @api private
    private def check_dependencies!
      require 'openid_connect'
    rescue LoadError
      raise OAuthDependencyError,
            'OAuth functionality requires the openid_connect gem. Add "gem \'openid_connect\'" to your Gemfile.'
    end

    # OpenID Connect Client Credentials flow implementation using discovery.
    #
    # This provides a secure OIDC Client Credentials flow implementation with
    # automatic endpoint discovery. Works seamlessly OIDC-compliant providers
    # that support discovery.
    #
    # @example
    #   oauth = OAuth.new(
    #     client_id: 'kessel-client',
    #     client_secret: 'super-secret-key',
    #     token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
    #   )
    #
    #   # Get current access token (automatically cached and refreshed)
    #   token = oauth.token
    class OAuth
      include Kessel::Auth

      # OAuth client identifier.
      # @return [String] The client ID
      attr_reader :client_id

      # OIDC issuer URL for discovery.
      # @return [String] The issuer URL
      attr_reader :token_endpoint

      # Creates a new OIDC client with specified token endpoint.
      #
      # @param client_id [String] OIDC client identifier
      # @param client_secret [String] OIDC client secret
      # @param token_endpoint [String] OIDC token endpoint URL
      #
      # @raise [OAuthDependencyError] if the openid_connect gem is not available
      # @raise [OAuthAuthenticationError] if authentication fails
      #
      # @example
      #   oauth = OAuth.new(
      #     client_id: 'my-app',
      #     client_secret: 'secret',
      #     token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
      #   )
      def initialize(client_id:, client_secret:, token_endpoint:)
        check_dependencies!

        @client_id = client_id
        @client_secret = client_secret
        @token_endpoint = token_endpoint
        @token_mutex = Mutex.new
      end

      # Gets the current access token with automatic caching and refresh.
      #
      # Uses OIDC Client Credentials flow with automatic token caching,
      # expiration checking, and refresh logic.
      #
      # @return [String] A valid access token
      # @raise [OAuthAuthenticationError] if token acquisition fails
      #
      # @example
      #   token = oauth.token
      #   # Use token in Authorization header: "Bearer #{token}"
      def token
        client_credentials_token['access_token']
      rescue StandardError => e
        raise OAuthAuthenticationError, "Failed to obtain OAuth token: #{e.message}"
      end

      def refresh
        client = create_oidc_client

        request_params = {
          grant_type: 'client_credentials',
          client_id: @client_id,
          client_secret: @client_secret
        }

        token_data = client.access_token!(request_params)
        RefreshTokenResponse.new(
          access_token: token_data.access_token,
          expires_in: token_data.expires_in,
        )
      end

      private

      # Forces a token refresh.
      #
      # @return [String] The new access token
      # @raise [OAuthAuthenticationError] if token refresh fails
      #
      # @example
      #   oauth.refresh_token  # Force refresh
      def refresh_token
        @token_mutex.synchronize do
          # Clear cached token to force refresh
          @cached_token = nil
        end
        token
      end

      # Checks if we have a valid cached token.
      #
      # @return [Boolean] true if token exists and not expired
      def token_valid?
        return false unless @cached_token

        expires_at = @cached_token['expires_at']
        return false unless expires_at

        Time.now.to_i < expires_at
      rescue StandardError
        false
      end

      # Creates an OIDC client using discovered configuration.
      #
      # @return [OpenIDConnect::Client] Configured OIDC client
      # @api private
      def create_oidc_client
        ::OpenIDConnect::Client.new(
          identifier: @client_id,
          secret: @client_secret,
          token_endpoint: @token_endpoint,
        )
      end

      # Gets or creates a client credentials token.
      #
      # Uses double-checked locking pattern for thread safety.
      #
      # @return [Hash] Hash containing access token and expiration info
      # @api private
      def client_credentials_token
        # Fast path: check without lock if token is valid
        return @cached_token if @cached_token && token_valid?

        # Slow path: acquire lock and check again
        @token_mutex.synchronize do
          # Double-check: another thread might have refreshed the token
          return @cached_token if @cached_token && token_valid?

          response = refresh

          @cached_token = {
            'access_token' => response.access_token,
            'expires_at' => Time.now.to_i + (response.expires_in || 3600)
          }
        end
      rescue StandardError => e
        raise OAuthAuthenticationError, "Failed to obtain client credentials token: #{e.message}"
      end
    end

    # gRPC interceptor that adds OIDC Bearer tokens to requests.
    #
    # This interceptor automatically adds Authorization headers with OIDC
    # Bearer tokens to all gRPC requests. It integrates with the OAuth client
    # to handle token refresh automatically via OpenID Connect discovery.
    #
    # @example
    #   oauth = OAuth.new(client_id: 'app', client_secret: 'secret', token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token')
    #   interceptor = OAuthInterceptor.new(oauth)
    #
    #   # Use with gRPC client
    #   client = Service::Stub.new('localhost:9000', creds, interceptors: [interceptor])
    class OAuthInterceptor < GRPC::ClientInterceptor
      # Creates a new OAuth interceptor.
      #
      # @param oauth_client [OAuth] The OAuth client to use for authentication
      #
      # @example
      #   oauth = OAuth.new(client_id: 'app', client_secret: 'secret', token_endpoint: 'https://auth.com/protocol/openid-connect/token')
      #   interceptor = OAuthInterceptor.new(oauth)
      def initialize(oauth_client)
        @oauth_client = oauth_client
        super()
      end

      # Intercepts gRPC requests to add OAuth authentication.
      #
      # @param request [Object] The gRPC request object (unused)
      # @param call [GRPC::ActiveCall] The gRPC call object (unused)
      # @param method [String] The gRPC method being called (unused)
      # @param metadata [Hash] The request metadata
      # @return [Object] The response from the intercepted call
      #
      # @api private
      # rubocop:disable Lint/UnusedMethodArgument
      def request_response(request:, call:, method:, metadata:)
        add_auth_metadata(metadata)
        yield
      end
      # rubocop:enable Lint/UnusedMethodArgument

      # Intercepts client streaming gRPC requests to add OAuth authentication.
      #
      # @param requests [Enumerator] The request stream (unused)
      # @param call [GRPC::ActiveCall] The gRPC call object (unused)
      # @param method [String] The gRPC method being called (unused)
      # @param metadata [Hash] The request metadata
      # @return [Object] The response from the intercepted call
      #
      # @api private
      # rubocop:disable Lint/UnusedMethodArgument
      def client_streamer(requests:, call:, method:, metadata:)
        add_auth_metadata(metadata)
        yield
      end
      # rubocop:enable Lint/UnusedMethodArgument

      # Intercepts server streaming gRPC requests to add OAuth authentication.
      #
      # @param request [Object] The gRPC request object (unused)
      # @param call [GRPC::ActiveCall] The gRPC call object (unused)
      # @param method [String] The gRPC method being called (unused)
      # @param metadata [Hash] The request metadata
      # @return [Enumerator] The response stream from the intercepted call
      #
      # @api private
      # rubocop:disable Lint/UnusedMethodArgument
      def server_streamer(request:, call:, method:, metadata:)
        add_auth_metadata(metadata)
        yield
      end
      # rubocop:enable Lint/UnusedMethodArgument

      # Intercepts bidirectional streaming gRPC requests to add OAuth authentication.
      #
      # @param requests [Enumerator] The request stream (unused)
      # @param call [GRPC::ActiveCall] The gRPC call object (unused)
      # @param method [String] The gRPC method being called (unused)
      # @param metadata [Hash] The request metadata
      # @return [Enumerator] The response stream from the intercepted call
      #
      # @api private
      # rubocop:disable Lint/UnusedMethodArgument
      def bidi_streamer(requests:, call:, method:, metadata:)
        add_auth_metadata(metadata)
        yield
      end
      # rubocop:enable Lint/UnusedMethodArgument

      private

      # Adds OAuth Bearer token to the request metadata.
      #
      # @param metadata [Hash] The request metadata hash to modify
      # @api private
      def add_auth_metadata(metadata)
        token = @oauth_client.token
        metadata['authorization'] = "Bearer #{token}"
      end
    end
  end
end
