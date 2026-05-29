# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'OAuth2ClientCredentials thundering herd prevention' do
  let(:client_id) { 'test-client' }
  let(:client_secret) { 'test-secret' }
  let(:token_endpoint) { 'https://auth.example.com/token' }
  let(:num_threads) { 20 }

  let(:counter_mutex) { Mutex.new }
  let(:sso_call_count) { { value: 0 } }
  let(:mock_client) { double('OpenIDConnect::Client') }

  let(:oauth) do
    Kessel::Auth::OAuth2ClientCredentials.new(
      client_id: client_id,
      client_secret: client_secret,
      token_endpoint: token_endpoint
    )
  end

  before do
    stub_const('OpenIDConnect', Module.new)
    stub_const('OpenIDConnect::Client', Class.new)
    allow_any_instance_of(Kessel::Auth::OAuth2ClientCredentials).to receive(:require)
      .with('openid_connect')
      .and_return(true)

    mu = counter_mutex
    count = sso_call_count
    allow(oauth).to receive(:create_oidc_client).and_return(mock_client)
    allow(mock_client).to receive(:access_token!) do
      mu.synchronize { count[:value] += 1 }
      sleep 0.05
      double('token_response', access_token: 'refreshed-token', expires_in: 3600)
    end
  end

  def run_concurrent_get_token(oauth, num_threads, **kwargs)
    barrier = Queue.new
    results = Queue.new

    threads = num_threads.times.map do
      Thread.new do
        barrier.pop
        token = oauth.get_token(**kwargs)
        results.push(token)
      rescue StandardError => e
        results.push(e)
      end
    end

    num_threads.times { barrier.push(:go) }
    threads.each(&:join)

    num_threads.times.map { results.pop }
  end

  context 'with a stale token (inside the 300s early-refresh window)' do
    before do
      stale_token = Kessel::Auth::RefreshTokenResponse.new('stale-token', Time.now + 60)
      oauth.instance_variable_set(:@cached_token, stale_token)
    end

    it 'results in exactly 1 SSO call when 20 threads refresh concurrently' do
      tokens = run_concurrent_get_token(oauth, num_threads)

      expect(sso_call_count[:value]).to eq(1)
      tokens.each do |token|
        expect(token).to be_a(Kessel::Auth::RefreshTokenResponse)
        expect(token.access_token).to eq('refreshed-token')
      end
    end
  end

  context 'with concurrent force_refresh: true calls' do
    before do
      valid_token = Kessel::Auth::RefreshTokenResponse.new('valid-token', Time.now + 3600)
      oauth.instance_variable_set(:@cached_token, valid_token)
    end

    it 'results in exactly 1 SSO call when 20 threads force-refresh concurrently' do
      tokens = run_concurrent_get_token(oauth, num_threads, force_refresh: true)

      expect(sso_call_count[:value]).to eq(1)
      tokens.each do |token|
        expect(token).to be_a(Kessel::Auth::RefreshTokenResponse)
        expect(token.access_token).to eq('refreshed-token')
      end
    end
  end

  context 'with a cold start (no cached token)' do
    it 'results in exactly 1 SSO call when 20 threads start concurrently' do
      tokens = run_concurrent_get_token(oauth, num_threads)

      expect(sso_call_count[:value]).to eq(1)
      tokens.each do |token|
        expect(token).to be_a(Kessel::Auth::RefreshTokenResponse)
        expect(token.access_token).to eq('refreshed-token')
      end
    end
  end
end
