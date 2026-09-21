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

    it 'shares one transient retry sequence across concurrent callers' do
      calls = 0
      allow(oauth).to receive(:sleep)
      allow(oauth).to receive(:rand).and_return(0.0)
      allow(mock_client).to receive(:access_token!) do
        call_number = counter_mutex.synchronize do
          calls += 1
          calls
        end
        raise Timeout::Error, 'temporary timeout' if call_number <= 3

        double('token_response', access_token: 'refreshed-token', expires_in: 3600)
      end

      tokens = run_concurrent_get_token(oauth, num_threads)

      expect(calls).to eq(4)
      tokens.each { |token| expect(token.access_token).to eq('refreshed-token') }
    end

    it 'coalesces concurrent callers with custom retry settings' do
      custom_oauth = Kessel::Auth::OAuth2ClientCredentials.new(
        client_id: client_id,
        client_secret: client_secret,
        token_endpoint: token_endpoint,
        retry: { max_retries: 2, base_delay: 0.1, max_delay: 0.2, jitter: :none }
      )
      calls = 0
      allow(custom_oauth).to receive(:create_oidc_client).and_return(mock_client)
      allow(custom_oauth).to receive(:sleep)
      allow(mock_client).to receive(:access_token!) do
        call_number = counter_mutex.synchronize do
          calls += 1
          calls
        end
        raise Timeout::Error, 'temporary timeout' if call_number <= 2

        double('token_response', access_token: 'custom-refreshed-token', expires_in: 3600)
      end

      tokens = run_concurrent_get_token(custom_oauth, num_threads)

      expect(calls).to eq(3)
      tokens.each { |token| expect(token.access_token).to eq('custom-refreshed-token') }
    end

    it 'lets an older failed generation use a later successful cache' do
      registration_started = Queue.new
      release_registration = Queue.new
      registration_mutex = Mutex.new
      first_registration = true
      allow(oauth).to receive(:register_generation).and_wrap_original do |original|
        generation = original.call
        gate = registration_mutex.synchronize do
          next false unless first_registration

          first_registration = false
          true
        end
        if gate
          registration_started << generation
          release_registration.pop
        end
        generation
      end
      allow(oauth).to receive(:sleep)
      allow(oauth).to receive(:rand).and_return(0.0)
      raw_failure = Timeout::Error.new('persistent timeout')
      allow(mock_client).to receive(:access_token!).and_raise(raw_failure)
      result = Queue.new
      old_waiter = Thread.new do
        result << oauth.get_token
      rescue StandardError => e
        result << e
      end

      expect(registration_started.pop).to eq(0)
      expect { oauth.get_token }.to raise_error(Kessel::Auth::OAuthAuthenticationError)

      allow(mock_client).to receive(:access_token!).and_return(
        double('token_response', access_token: 'newer-token', expires_in: 3600)
      )
      expect(oauth.get_token.access_token).to eq('newer-token')

      release_registration << :continue
      old_waiter.join
      expect(result.pop.access_token).to eq('newer-token')
    end

    it 'coalesces persistent terminal failures and shares their raw cause' do
      registration_queue = Queue.new
      raw_failure = Timeout::Error.new('persistent timeout')
      registrations = 0
      registration_mutex = Mutex.new
      allow(oauth).to receive(:register_generation).and_wrap_original do |original|
        generation = original.call
        registration_mutex.synchronize { registrations += 1 }
        registration_queue << generation
        generation
      end
      allow(oauth).to receive(:sleep)
      allow(oauth).to receive(:rand).and_return(0.0)
      calls = 0
      first_request = true
      allow(mock_client).to receive(:access_token!) do
        if first_request
          first_request = false
          num_threads.times { registration_queue.pop }
        end
        calls += 1
        raise raw_failure
      end

      errors = run_concurrent_get_token(oauth, num_threads)

      expect(registrations).to eq(num_threads)
      expect(calls).to eq(4)
      expect(errors).to all(be_a(Kessel::Auth::OAuthAuthenticationError))
      expect(errors.map(&:message).uniq).to eq(['Failed to obtain client credentials token: persistent timeout'])
      expect(errors.map(&:cause).uniq).to eq([raw_failure])
      expect(oauth.instance_variable_get(:@generation_users)).to be_empty
      expect(oauth.instance_variable_get(:@generation_failures)).to be_empty
    end

    it 'cleans the failure registry so a later call can retry and succeed' do
      allow(oauth).to receive(:sleep)
      allow(oauth).to receive(:rand).and_return(0.0)
      calls = 0
      allow(mock_client).to receive(:access_token!) do
        calls += 1
        raise Timeout::Error, 'persistent timeout' if calls <= 4

        double('token_response', access_token: 'recovered-token', expires_in: 3600)
      end

      expect { oauth.get_token }.to raise_error(Kessel::Auth::OAuthAuthenticationError)
      expect(oauth.instance_variable_get(:@generation_users)).to be_empty
      expect(oauth.instance_variable_get(:@generation_failures)).to be_empty

      expect(oauth.get_token.access_token).to eq('recovered-token')
      expect(calls).to eq(5)
    end
  end

  it 'coalesces concurrent force-refresh failures and permits later force refresh' do
    valid_token = Kessel::Auth::RefreshTokenResponse.new('cached-token', Time.now + 3600)
    oauth.instance_variable_set(:@cached_token, valid_token)
    registration_queue = Queue.new
    raw_failure = Timeout::Error.new('persistent timeout')
    allow(oauth).to receive(:register_generation).and_wrap_original do |original|
      generation = original.call
      registration_queue << generation
      generation
    end
    allow(oauth).to receive(:sleep)
    allow(oauth).to receive(:rand).and_return(0.0)
    calls = 0
    first_request = true
    allow(mock_client).to receive(:access_token!) do
      if first_request
        first_request = false
        num_threads.times { registration_queue.pop }
      end
      calls += 1
      raise raw_failure if calls <= 4

      double('token_response', access_token: 'forced-recovery-token', expires_in: 3600)
    end

    errors = run_concurrent_get_token(oauth, num_threads, force_refresh: true)

    expect(calls).to eq(4)
    expect(errors).to all(be_a(Kessel::Auth::OAuthAuthenticationError))
    expect(errors.map(&:cause).uniq).to eq([raw_failure])
    expect(oauth.get_token.access_token).to eq('cached-token')
    expect(calls).to eq(4)
    expect(oauth.get_token(force_refresh: true).access_token).to eq('forced-recovery-token')
    expect(calls).to eq(5)
  end
end
