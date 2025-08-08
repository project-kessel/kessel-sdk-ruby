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
                                                            })

        oauth.send(:refresh)
      end

      context 'when refresh fails' do
        before do
          allow(oauth).to receive(:create_oidc_client).and_raise(StandardError, 'Refresh failed')
        end

        it 'raises StandardError' do
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
end
