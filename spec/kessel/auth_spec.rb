# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kessel::Auth do
  describe 'module structure' do
    it 'defines the Auth module' do
      expect(defined?(Kessel::Auth)).to eq('constant')
    end

    it 'defines exception classes' do
      expect(defined?(Kessel::Auth::OAuthDependencyError)).to eq('constant')
      expect(defined?(Kessel::Auth::OAuthAuthenticationError)).to eq('constant')
    end

    it 'defines data structures' do
      expect(defined?(Kessel::Auth::OIDCDiscoveryMetadata)).to eq('constant')
      expect(defined?(Kessel::Auth::RefreshTokenResponse)).to eq('constant')
    end

    it 'defines OAuth2ClientCredentials class' do
      expect(defined?(Kessel::Auth::OAuth2ClientCredentials)).to eq('constant')
    end

    it 'defines AuthRequest module' do
      expect(defined?(Kessel::Auth::AuthRequest)).to eq('constant')
    end
  end

  describe 'exception classes' do
    describe 'OAuthDependencyError' do
      it 'inherits from StandardError' do
        expect(Kessel::Auth::OAuthDependencyError.new).to be_a(StandardError)
      end

      it 'accepts a custom message' do
        error = Kessel::Auth::OAuthDependencyError.new('Custom message')
        expect(error.message).to eq('Custom message')
      end
    end

    describe 'OAuthAuthenticationError' do
      it 'inherits from StandardError' do
        expect(Kessel::Auth::OAuthAuthenticationError.new).to be_a(StandardError)
      end

      it 'accepts a custom message' do
        error = Kessel::Auth::OAuthAuthenticationError.new('Auth failed')
        expect(error.message).to eq('Auth failed')
      end
    end
  end

  describe 'OIDCDiscoveryMetadata' do
    it 'stores token endpoint' do
      metadata = Kessel::Auth::OIDCDiscoveryMetadata.new('https://example.com/token')
      expect(metadata.token_endpoint).to eq('https://example.com/token')
    end

    it 'allows setting token endpoint' do
      metadata = Kessel::Auth::OIDCDiscoveryMetadata.new('https://example.com/token')
      metadata.token_endpoint = 'https://new.example.com/token'
      expect(metadata.token_endpoint).to eq('https://new.example.com/token')
    end
  end

  describe 'RefreshTokenResponse' do
    it 'stores access token and expires_at' do
      response = Kessel::Auth::RefreshTokenResponse.new('token123', Time.now + 3600)
      expect(response.access_token).to eq('token123')
      expect(response.expires_at).to be_a(Time)
    end

    it 'allows setting attributes' do
      response = Kessel::Auth::RefreshTokenResponse.new('token123', Time.now + 3600)
      response.access_token = 'new_token'
      response.expires_at = Time.now + 7200
      expect(response.access_token).to eq('new_token')
      expect(response.expires_at).to be_a(Time)
    end
  end

  describe 'OAuth2ClientCredentials' do
    let(:client_id) { 'test-client' }
    let(:client_secret) { 'test-secret' }
    let(:token_endpoint) { 'https://auth.example.com/token' }
    let(:mock_client) { double('OpenIDConnect::Client') }
    let(:mock_token_response) do
      double('token_response', access_token: 'test-token', expires_in: 3600)
    end

    before do
      # Mock OpenIDConnect dependencies
      stub_const('OpenIDConnect', Module.new)
      stub_const('OpenIDConnect::Client', Class.new do
        def self.new(options = {})
          # Return a mock client
        end
      end)

      # Mock the require call to simulate dependency being available
      allow_any_instance_of(Kessel::Auth::OAuth2ClientCredentials).to receive(:require)
        .with('openid_connect')
        .and_return(true)
    end

    describe '#initialize' do
      context 'when openid_connect gem is available' do
        it 'creates OAuth2ClientCredentials instance with required parameters' do
          oauth = Kessel::Auth::OAuth2ClientCredentials.new(
            client_id: client_id,
            client_secret: client_secret,
            token_endpoint: token_endpoint
          )

          expect(oauth.instance_variable_get(:@client_id)).to eq(client_id)
          expect(oauth.instance_variable_get(:@token_endpoint)).to eq(token_endpoint)
        end
      end

      context 'when openid_connect gem is missing' do
        before do
          allow_any_instance_of(Kessel::Auth::OAuth2ClientCredentials).to receive(:require)
            .with('openid_connect')
            .and_raise(LoadError)
        end

        it 'raises OAuthDependencyError' do
          expect do
            Kessel::Auth::OAuth2ClientCredentials.new(
              client_id: client_id,
              client_secret: client_secret,
              token_endpoint: token_endpoint
            )
          end.to raise_error(Kessel::Auth::OAuthDependencyError, /OAuth functionality requires the openid_connect gem/)
        end
      end

      it 'uses immutable default retry configuration' do
        oauth = Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint
        )

        expect(oauth.instance_variable_get(:@retry_config)).to eq(
          max_retries: 3,
          base_delay: 0.5,
          max_delay: 2.0,
          jitter: :full
        )
        expect(oauth.instance_variable_get(:@retry_config)).to be_frozen
      end

      it 'copies custom retry configuration before freezing it' do
        retry_options = { max_retries: 1, base_delay: 0.25, max_delay: 0.75, jitter: :none }
        oauth = Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint,
          retry: retry_options
        )
        retry_options[:max_retries] = 99

        expect(oauth.instance_variable_get(:@retry_config)).to eq(
          max_retries: 1,
          base_delay: 0.25,
          max_delay: 0.75,
          jitter: :none
        )
        expect(oauth.instance_variable_get(:@retry_config)).to be_frozen
      end

      it 'rejects unknown keywords' do
        expect do
          Kessel::Auth::OAuth2ClientCredentials.new(
            client_id: client_id,
            client_secret: client_secret,
            token_endpoint: token_endpoint,
            unexpected: true
          )
        end.to raise_error(ArgumentError)
      end

      [
        nil,
        'not-a-hash',
        { 'max_retries' => 1 },
        { unknown: 1 },
        { max_retries: -1 },
        { max_retries: nil },
        { max_retries: 1.5 },
        { base_delay: 0 },
        { base_delay: -0.1 },
        { base_delay: Float::INFINITY },
        { max_delay: 0 },
        { max_delay: -1 },
        { max_delay: Float::NAN },
        { max_delay: '2' },
        { jitter: :random },
        { jitter: 'full' },
        { jitter: nil }
      ].each do |invalid_retry_options|
        it "rejects invalid retry configuration #{invalid_retry_options.inspect}" do
          expect do
            Kessel::Auth::OAuth2ClientCredentials.new(
              client_id: client_id,
              client_secret: client_secret,
              token_endpoint: token_endpoint,
              retry: invalid_retry_options
            )
          end.to raise_error(ArgumentError)
        end
      end
    end

    describe '#get_token' do
      let(:oauth) do
        Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint
        )
      end

      before do
        allow(oauth).to receive(:create_oidc_client).and_return(mock_client)
        allow(mock_client).to receive(:access_token!).and_return(mock_token_response)
      end

      it 'returns RefreshTokenResponse when called' do
        result = oauth.get_token
        expect(result).to be_a(Kessel::Auth::RefreshTokenResponse)
        expect(result.access_token).to eq('test-token')
      end

      it 'preserves the cached token and generation when all retries fail' do
        cached_token = Kessel::Auth::RefreshTokenResponse.new('stale-token', Time.now + 60)
        oauth.instance_variable_set(:@cached_token, cached_token)
        oauth.instance_variable_set(:@generation, 7)
        calls = 0
        allow(oauth).to receive(:sleep)
        allow(oauth).to receive(:rand).and_return(0.0)
        allow(mock_client).to receive(:access_token!) do
          calls += 1
          raise Timeout::Error, 'temporary timeout'
        end

        expect { oauth.get_token }.to raise_error(Kessel::Auth::OAuthAuthenticationError)
        expect(calls).to eq(4)
        expect(oauth.instance_variable_get(:@cached_token)).to equal(cached_token)
        expect(oauth.instance_variable_get(:@generation)).to eq(7)
      end

      context 'when token retrieval fails' do
        before do
          allow(oauth).to receive(:create_oidc_client).and_raise(StandardError, 'Token request failed')
        end

        it 'raises OAuthAuthenticationError' do
          expect do
            oauth.get_token
          end.to raise_error(Kessel::Auth::OAuthAuthenticationError,
                             /Failed to obtain client credentials token.*Token request failed/)
        end
      end
    end

    describe '#refresh' do
      let(:oauth) do
        Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint
        )
      end

      before do
        allow(oauth).to receive(:create_oidc_client).and_return(mock_client)
        allow(mock_client).to receive(:access_token!).and_return(mock_token_response)
      end

      it 'returns RefreshTokenResponse with new token data' do
        result = oauth.send(:refresh)

        expect(result).to be_a(Kessel::Auth::RefreshTokenResponse)
        expect(result.access_token).to eq('test-token')
        expect(result.expires_at).to be_a(Time)
      end

      it 'calls access_token! with correct parameters' do
        expect(mock_client).to receive(:access_token!).with({
                                                              grant_type: 'client_credentials',
                                                              client_id: client_id,
                                                              client_secret: client_secret
                                                            }).and_return(mock_token_response)

        oauth.send(:refresh)
      end

      context 'when the token endpoint returns a Rack OAuth error' do
        let(:rack_error_class) do
          Class.new(StandardError) do
            attr_reader :status

            def initialize(status)
              @status = status
              super("OAuth error #{status}")
            end
          end
        end

        before do
          stub_const('Rack', Module.new)
          stub_const('Rack::OAuth2', Module.new)
          stub_const('Rack::OAuth2::Client', Module.new)
          stub_const('Rack::OAuth2::Client::Error', rack_error_class)
          allow(oauth).to receive(:sleep)
          allow(oauth).to receive(:rand).and_return(0.1, 0.2, 0.3)
        end

        [429, 500, 599].each do |status|
          context "with status #{status}" do
            it 'retries three times before succeeding' do
              calls = 0
              error = rack_error_class.new(status)
              allow(mock_client).to receive(:access_token!) do
                calls += 1
                raise error if calls <= 3

                mock_token_response
              end

              expect(oauth.send(:refresh).access_token).to eq('test-token')
              expect(calls).to eq(4)
            end
          end
        end

        it 'does not retry an OAuth 4xx error' do
          error = rack_error_class.new(400)
          expect(mock_client).to receive(:access_token!).once.and_raise(error)
          expect(oauth).not_to receive(:sleep)

          expect { oauth.send(:refresh) }.to raise_error(rack_error_class, /OAuth error 400/)
        end
      end

      it 'retries transient timeout errors with full-jitter caps' do
        calls = 0
        allow(mock_client).to receive(:access_token!) do
          calls += 1
          raise Timeout::Error, 'temporary timeout' if calls <= 3

          mock_token_response
        end
        expect(oauth).to receive(:rand).with(0.5).and_return(0.1).ordered
        expect(oauth).to receive(:sleep).with(0.1).ordered
        expect(oauth).to receive(:rand).with(1.0).and_return(0.2).ordered
        expect(oauth).to receive(:sleep).with(0.2).ordered
        expect(oauth).to receive(:rand).with(2.0).and_return(0.3).ordered
        expect(oauth).to receive(:sleep).with(0.3).ordered

        expect(oauth.send(:refresh).access_token).to eq('test-token')
        expect(calls).to eq(4)
      end

      it 'retries transient connection errors' do
        calls = 0
        allow(oauth).to receive(:sleep)
        allow(oauth).to receive(:rand).and_return(0.0)
        allow(mock_client).to receive(:access_token!) do
          calls += 1
          raise Errno::ECONNRESET, 'connection reset' if calls <= 3

          mock_token_response
        end

        expect(oauth.send(:refresh).access_token).to eq('test-token')
        expect(calls).to eq(4)
      end

      it 'uses custom retry count and capped full-jitter schedule' do
        custom_oauth = Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint,
          retry: { max_retries: 2, base_delay: 0.25, max_delay: 0.75, jitter: :full }
        )
        calls = 0
        allow(custom_oauth).to receive(:create_oidc_client).and_return(mock_client)
        allow(mock_client).to receive(:access_token!) do
          calls += 1
          raise Timeout::Error, 'temporary timeout' if calls <= 2

          mock_token_response
        end
        expect(custom_oauth).to receive(:rand).with(0.25).and_return(0.1).ordered
        expect(custom_oauth).to receive(:sleep).with(0.1).ordered
        expect(custom_oauth).to receive(:rand).with(0.5).and_return(0.2).ordered
        expect(custom_oauth).to receive(:sleep).with(0.2).ordered

        expect(custom_oauth.send(:refresh).access_token).to eq('test-token')
        expect(calls).to eq(3)
      end

      it 'uses exact capped delays without random jitter' do
        custom_oauth = Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint,
          retry: { max_retries: 4, base_delay: 0.75, max_delay: 1.5, jitter: :none }
        )
        calls = 0
        allow(custom_oauth).to receive(:create_oidc_client).and_return(mock_client)
        allow(mock_client).to receive(:access_token!) do
          calls += 1
          raise Timeout::Error, 'temporary timeout' if calls <= 4

          mock_token_response
        end
        expect(custom_oauth).not_to receive(:rand)
        expect(custom_oauth).to receive(:sleep).with(0.75).ordered
        expect(custom_oauth).to receive(:sleep).with(1.5).exactly(3).times.ordered

        expect(custom_oauth.send(:refresh).access_token).to eq('test-token')
        expect(calls).to eq(5)
      end

      it 'makes one token request when retries are disabled' do
        custom_oauth = Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint,
          retry: { max_retries: 0 }
        )
        error = Timeout::Error.new('temporary timeout')
        allow(custom_oauth).to receive(:create_oidc_client).and_return(mock_client)
        expect(mock_client).to receive(:access_token!).once.and_raise(error)
        expect(custom_oauth).not_to receive(:sleep)
        expect(custom_oauth).not_to receive(:rand)

        expect { custom_oauth.send(:refresh) }.to raise_error(Timeout::Error, 'temporary timeout')
      end

      %w[ConnectionFailed TimeoutError].each do |faraday_error_name|
        context "when Faraday::#{faraday_error_name} is raised" do
          let(:faraday_error_class) { Class.new(StandardError) }

          before do
            stub_const('Faraday', Module.new)
            stub_const("Faraday::#{faraday_error_name}", faraday_error_class)
            allow(oauth).to receive(:sleep)
            allow(oauth).to receive(:rand).and_return(0.0)
          end

          it 'retries the token request before succeeding' do
            calls = 0
            allow(mock_client).to receive(:access_token!) do
              calls += 1
              raise faraday_error_class, 'temporary Faraday failure' if calls <= 3

              mock_token_response
            end

            expect(oauth.send(:refresh).access_token).to eq('test-token')
            expect(calls).to eq(4)
          end
        end
      end

      context 'when refresh fails' do
        before do
          allow(oauth).to receive(:create_oidc_client).and_raise(StandardError, 'Refresh failed')
        end

        it 'raises StandardError' do
          expect(oauth).to receive(:create_oidc_client).once.and_raise(StandardError, 'Refresh failed')

          expect do
            oauth.send(:refresh)
          end.to raise_error(StandardError, 'Refresh failed')
        end
      end
    end

    describe '#token_valid?' do
      let(:oauth) do
        Kessel::Auth::OAuth2ClientCredentials.new(
          client_id: client_id,
          client_secret: client_secret,
          token_endpoint: token_endpoint
        )
      end

      context 'when token is valid' do
        before do
          # Mock a valid cached token (RefreshTokenResponse object)
          valid_token = Kessel::Auth::RefreshTokenResponse.new('valid-token', Time.now + 3600)
          oauth.instance_variable_set(:@cached_token, valid_token)
        end

        it 'returns true' do
          expect(oauth.send(:token_valid?)).to be true
        end
      end

      context 'when token is expired' do
        before do
          # Mock an expired cached token
          expired_token = Kessel::Auth::RefreshTokenResponse.new('expired-token', Time.now - 3600)
          oauth.instance_variable_set(:@cached_token, expired_token)
        end

        it 'returns false' do
          expect(oauth.send(:token_valid?)).to be false
        end
      end

      context 'when no token is cached' do
        it 'returns false' do
          expect(oauth.send(:token_valid?)).to be false
        end
      end
    end
  end

  describe '#oauth2_auth_request' do
    include Kessel::Auth

    let(:mock_credentials) { double('OAuth2ClientCredentials') }

    it 'creates OAuth2AuthRequest with credentials' do
      result = oauth2_auth_request(mock_credentials)

      expect(result).to be_a(Kessel::Auth::OAuth2AuthRequest)
      expect(result.instance_variable_get(:@credentials)).to eq(mock_credentials)
    end
  end

  describe 'OAuth2AuthRequest' do
    let(:mock_credentials) { double('OAuth2ClientCredentials') }
    let(:mock_token) { double('token', access_token: 'test-token-123') }
    let(:mock_request) { {} }
    let(:auth_request) { Kessel::Auth::OAuth2AuthRequest.new(mock_credentials) }

    describe '#initialize' do
      it 'stores credentials' do
        expect(auth_request.instance_variable_get(:@credentials)).to eq(mock_credentials)
      end
    end

    describe '#configure_request' do
      before do
        allow(mock_credentials).to receive(:get_token).and_return(mock_token)
      end

      it 'gets token from credentials' do
        expect(mock_credentials).to receive(:get_token)

        auth_request.configure_request(mock_request)
      end

      it 'sets authorization header with Bearer token' do
        auth_request.configure_request(mock_request)

        expect(mock_request['authorization']).to eq('Bearer test-token-123')
      end

      context 'when token access_token is nil' do
        let(:mock_token) { double('token', access_token: nil) }

        it 'sets authorization header with Bearer nil' do
          auth_request.configure_request(mock_request)

          expect(mock_request['authorization']).to eq('Bearer ')
        end
      end
    end
  end

  describe 'AuthRequest module' do
    let(:test_class) do
      Class.new do
        include Kessel::Auth::AuthRequest
      end
    end

    it 'requires implementation of configure_request method' do
      instance = test_class.new

      expect do
        instance.configure_request({})
      end.to raise_error(NotImplementedError, /must implement #configure_request/)
    end
  end
end
