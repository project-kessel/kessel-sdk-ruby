# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kessel::Auth::RetryHandler do
  let(:test_class) do
    Class.new do
      include Kessel::Auth::RetryHandler

      # Expose private methods for testing
      public :backoff_delay, :retryable_http_error?, :extract_http_status,
             :backoff_delay_for_http_error, :extract_retry_after, :parse_retry_after_date
    end
  end

  let(:handler) { test_class.new }

  before do
    # Stub sleep to avoid actual delays in tests
    allow(handler).to receive(:sleep)
  end

  describe '#with_retry' do
    context 'when the block succeeds on the first attempt' do
      it 'returns the block result without retrying' do
        result = handler.with_retry { 'success' }

        expect(result).to eq('success')
        expect(handler).not_to have_received(:sleep)
      end
    end

    context 'when the block raises a retryable network error then succeeds' do
      it 'retries on Errno::ECONNREFUSED' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise Errno::ECONNREFUSED if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on Errno::ECONNRESET' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise Errno::ECONNRESET if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on Errno::ETIMEDOUT' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise Errno::ETIMEDOUT if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on SocketError' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise SocketError, 'getaddrinfo: Name or service not known' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on Net::OpenTimeout' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise Net::OpenTimeout, 'execution expired' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on Net::ReadTimeout' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise Net::ReadTimeout, 'Net::ReadTimeout' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on Timeout::Error' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise Timeout::Error, 'execution expired' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end
    end

    context 'when the block raises a retryable HTTP error then succeeds' do
      it 'retries on HTTP 429 in error message' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise StandardError, 'HTTP 429 Too Many Requests' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on HTTP 503 in error message' do
        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise StandardError, 'HTTP 503 Service Unavailable' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on error with status method returning 500' do
        error_class = Class.new(StandardError) do
          def status
            500
          end
        end

        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise error_class, 'Internal Server Error' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end

      it 'retries on error with response.status returning 502' do
        response = double('response', status: 502)
        error_class = Class.new(StandardError) do
          define_method(:response) { response }
        end

        attempt = 0
        result = handler.with_retry do
          attempt += 1
          raise error_class, 'Bad Gateway' if attempt == 1

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(handler).to have_received(:sleep).once
      end
    end

    context 'when retries are exhausted' do
      it 'raises the original error after max_retries' do
        expect do
          handler.with_retry(max_retries: 2) do
            raise Errno::ECONNREFUSED
          end
        end.to raise_error(Errno::ECONNREFUSED)

        expect(handler).to have_received(:sleep).exactly(2).times
      end

      it 'raises the original HTTP error after max_retries' do
        expect do
          handler.with_retry(max_retries: 2) do
            raise StandardError, 'HTTP 503 Service Unavailable'
          end
        end.to raise_error(StandardError, /503/)

        expect(handler).to have_received(:sleep).exactly(2).times
      end
    end

    context 'when the error is not retryable' do
      it 'raises immediately without retrying' do
        expect do
          handler.with_retry do
            raise ArgumentError, 'bad argument'
          end
        end.to raise_error(ArgumentError, 'bad argument')

        expect(handler).not_to have_received(:sleep)
      end

      it 'does not retry HTTP 400 errors' do
        expect do
          handler.with_retry do
            raise StandardError, 'HTTP 400 Bad Request'
          end
        end.to raise_error(StandardError, /400/)

        expect(handler).not_to have_received(:sleep)
      end

      it 'does not retry HTTP 401 errors' do
        expect do
          handler.with_retry do
            raise StandardError, 'HTTP 401 Unauthorized'
          end
        end.to raise_error(StandardError, /401/)

        expect(handler).not_to have_received(:sleep)
      end

      it 'does not retry HTTP 403 errors' do
        expect do
          handler.with_retry do
            raise StandardError, 'HTTP 403 Forbidden'
          end
        end.to raise_error(StandardError, /403/)

        expect(handler).not_to have_received(:sleep)
      end
    end

    context 'with custom retry configuration' do
      it 'respects custom max_retries' do
        attempt = 0
        expect do
          handler.with_retry(max_retries: 5) do
            attempt += 1
            raise Errno::ECONNREFUSED
          end
        end.to raise_error(Errno::ECONNREFUSED)

        expect(attempt).to eq(6) # 1 initial + 5 retries
        expect(handler).to have_received(:sleep).exactly(5).times
      end

      it 'succeeds on the last allowed retry' do
        attempt = 0
        result = handler.with_retry(max_retries: 3) do
          attempt += 1
          raise Errno::ECONNREFUSED if attempt <= 3

          'finally'
        end

        expect(result).to eq('finally')
        expect(handler).to have_received(:sleep).exactly(3).times
      end
    end

    context 'when retrying multiple times before success' do
      it 'retries up to max_retries then succeeds' do
        attempt = 0
        result = handler.with_retry(max_retries: 3) do
          attempt += 1
          raise Errno::ECONNRESET if attempt <= 2

          'recovered after 2 failures'
        end

        expect(result).to eq('recovered after 2 failures')
        expect(handler).to have_received(:sleep).exactly(2).times
      end
    end
  end

  describe '#backoff_delay' do
    it 'returns a value between 0 and base_delay for attempt 1' do
      100.times do
        delay = handler.backoff_delay(1, 0.5, 10.0)
        expect(delay).to be >= 0
        expect(delay).to be < 0.5
      end
    end

    it 'increases the upper bound exponentially' do
      # Attempt 1: [0, 0.5), Attempt 2: [0, 1.0), Attempt 3: [0, 2.0)
      delays = (1..3).map do |attempt|
        Array.new(100) { handler.backoff_delay(attempt, 0.5, 10.0) }
      end

      # Average delay should increase with attempt number (statistical)
      avg1 = delays[0].sum / delays[0].size
      avg2 = delays[1].sum / delays[1].size
      avg3 = delays[2].sum / delays[2].size
      expect(avg2).to be > avg1
      expect(avg3).to be > avg2
    end

    it 'caps delay at max_delay' do
      100.times do
        delay = handler.backoff_delay(20, 0.5, 2.0)
        expect(delay).to be >= 0
        expect(delay).to be < 2.0
      end
    end

    it 'applies full jitter (randomization)' do
      delays = Array.new(50) { handler.backoff_delay(2, 1.0, 10.0) }
      unique_delays = delays.uniq
      expect(unique_delays.size).to be > 1
    end
  end

  describe '#retryable_http_error?' do
    it 'returns true for 429 in message' do
      error = StandardError.new('HTTP 429 Too Many Requests')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for 500 in message' do
      error = StandardError.new('Internal Server Error 500')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for 502 in message' do
      error = StandardError.new('502 Bad Gateway')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for 503 in message' do
      error = StandardError.new('503 Service Unavailable')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for 504 in message' do
      error = StandardError.new('504 Gateway Timeout')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for 501 in message' do
      error = StandardError.new('501 Not Implemented')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for 505 in message' do
      error = StandardError.new('505 HTTP Version Not Supported')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for 507 in message' do
      error = StandardError.new('507 Insufficient Storage')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for error with status method returning 507' do
      error_class = Class.new(StandardError) { define_method(:status) { 507 } }
      error = error_class.new('Insufficient Storage')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for error with status method returning 599' do
      error_class = Class.new(StandardError) { define_method(:status) { 599 } }
      error = error_class.new('Network connect timeout error')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for "too many requests" in message' do
      error = StandardError.new('Rate limited: too many requests')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for "service unavailable" in message' do
      error = StandardError.new('The service is temporarily unavailable: service unavailable')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for error with status method' do
      error_class = Class.new(StandardError) { define_method(:status) { 429 } }
      error = error_class.new('rate limited')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns true for error with response.status' do
      response = double('response', status: 503)
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('unavailable')
      expect(handler.retryable_http_error?(error)).to be true
    end

    it 'returns false for 400 errors' do
      error = StandardError.new('HTTP 400 Bad Request')
      expect(handler.retryable_http_error?(error)).to be false
    end

    it 'returns false for 401 errors' do
      error = StandardError.new('HTTP 401 Unauthorized')
      expect(handler.retryable_http_error?(error)).to be false
    end

    it 'returns false for 404 errors' do
      error = StandardError.new('HTTP 404 Not Found')
      expect(handler.retryable_http_error?(error)).to be false
    end

    it 'returns false for generic errors' do
      error = StandardError.new('something went wrong')
      expect(handler.retryable_http_error?(error)).to be false
    end
  end

  describe '#extract_http_status' do
    it 'extracts status from error with status method' do
      error_class = Class.new(StandardError) { define_method(:status) { 503 } }
      error = error_class.new('unavailable')
      expect(handler.extract_http_status(error)).to eq(503)
    end

    it 'extracts status from error.response.status' do
      response = double('response', status: 429)
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')
      expect(handler.extract_http_status(error)).to eq(429)
    end

    it 'returns nil when error has no status' do
      error = StandardError.new('generic error')
      expect(handler.extract_http_status(error)).to be_nil
    end

    it 'returns nil when status is zero' do
      error_class = Class.new(StandardError) { define_method(:status) { 0 } }
      error = error_class.new('zero status')
      expect(handler.extract_http_status(error)).to be_nil
    end
  end

  describe '#extract_retry_after' do
    it 'extracts Retry-After from response hash-style access' do
      response = { 'Retry-After' => '2.5' }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')
      expect(handler.extract_retry_after(error)).to eq(2.5)
    end

    it 'extracts Retry-After from response.headers' do
      headers = { 'Retry-After' => '5' }
      response = double('response', headers: headers)
      allow(response).to receive(:respond_to?).with(:[]).and_return(false)
      allow(response).to receive(:respond_to?).with(:headers).and_return(true)
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')
      expect(handler.extract_retry_after(error)).to eq(5.0)
    end

    it 'returns nil when no response' do
      error = StandardError.new('no response')
      expect(handler.extract_retry_after(error)).to be_nil
    end

    it 'returns nil when Retry-After is zero' do
      response = { 'Retry-After' => '0' }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')
      expect(handler.extract_retry_after(error)).to be_nil
    end

    it 'parses HTTP-date Retry-After as seconds until target time' do
      future_time = Time.now + 60
      http_date = future_time.httpdate
      response = { 'Retry-After' => http_date }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')

      result = handler.extract_retry_after(error)
      expect(result).to be_a(Float)
      expect(result).to be > 0
      expect(result).to be <= 60
    end

    it 'returns nil for HTTP-date Retry-After in the past' do
      past_time = Time.now - 60
      http_date = past_time.httpdate
      response = { 'Retry-After' => http_date }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')

      expect(handler.extract_retry_after(error)).to be_nil
    end

    it 'returns nil for invalid non-numeric non-date Retry-After' do
      response = { 'Retry-After' => 'invalid-date-string' }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')

      expect(handler.extract_retry_after(error)).to be_nil
    end

    it 'returns nil for negative numeric Retry-After' do
      response = { 'Retry-After' => '-5' }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')

      expect(handler.extract_retry_after(error)).to be_nil
    end
  end

  describe '#parse_retry_after_date' do
    it 'returns seconds until a future HTTP-date' do
      future_time = Time.now + 120
      result = handler.parse_retry_after_date(future_time.httpdate)
      expect(result).to be_a(Float)
      expect(result).to be > 0
      expect(result).to be <= 120
    end

    it 'returns nil for a past HTTP-date' do
      past_time = Time.now - 30
      expect(handler.parse_retry_after_date(past_time.httpdate)).to be_nil
    end

    it 'returns nil for an invalid date string' do
      expect(handler.parse_retry_after_date('not-a-date')).to be_nil
    end
  end

  describe '#backoff_delay_for_http_error' do
    it 'uses Retry-After when present and larger than calculated delay' do
      response = { 'Retry-After' => '30' }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')

      allow(handler).to receive(:rand).and_return(0.5)
      delay = handler.backoff_delay_for_http_error(error, 1, 0.5, 10.0)

      expect(delay).to eq(30.0)
    end

    it 'uses calculated delay when larger than Retry-After' do
      response = { 'Retry-After' => '0.01' }
      error_class = Class.new(StandardError) { define_method(:response) { response } }
      error = error_class.new('rate limited')

      allow(handler).to receive(:rand).and_return(0.9)
      delay = handler.backoff_delay_for_http_error(error, 3, 1.0, 10.0)

      # Attempt 3: base * 2^2 = 4.0, * 0.9 = 3.6
      expect(delay).to eq(3.6)
    end

    it 'falls back to calculated delay when no Retry-After' do
      error = StandardError.new('HTTP 500 Internal Server Error')

      allow(handler).to receive(:rand).and_return(0.5)
      delay = handler.backoff_delay_for_http_error(error, 1, 1.0, 10.0)

      expect(delay).to eq(0.5) # 1.0 * 2^0 = 1.0 * 0.5
    end
  end
end
