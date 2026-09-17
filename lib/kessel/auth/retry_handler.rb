# frozen_string_literal: true

require 'net/http'
require 'time'
require 'timeout'

module Kessel
  module Auth
    # Retry logic with exponential backoff and jitter for transient HTTP failures.
    #
    # Handles connection errors, timeouts, HTTP 429 (Too Many Requests), and
    # 5xx server errors. Designed for OIDC discovery and token endpoint calls.
    #
    # @example
    #   include Kessel::Auth::RetryHandler
    #
    #   result = with_retry(max_retries: 3) do
    #     perform_http_call
    #   end
    #
    # @since 1.12.0
    module RetryHandler
      DEFAULT_MAX_RETRIES = 3
      DEFAULT_BASE_DELAY = 0.5 # seconds
      DEFAULT_MAX_DELAY = 10.0 # seconds

      # Network-level errors that always warrant a retry.
      RETRYABLE_NETWORK_ERRORS = [
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        IOError,
        SocketError
      ].freeze

      # HTTP status codes that warrant a retry (429 + all 5xx server errors).
      RETRYABLE_HTTP_STATUSES = ([429] + (500..599).to_a).freeze

      # Executes a block with retry logic using exponential backoff and jitter.
      #
      # Retries on network errors (connection refused, reset, timeout),
      # HTTP 429 (Too Many Requests), and 5xx server errors. Non-retryable
      # errors are re-raised immediately. When a 429 response includes a
      # Retry-After header, the delay honors that value.
      #
      # @param max_retries [Integer] Maximum number of retry attempts (default: 3)
      # @param base_delay [Float] Base delay in seconds for exponential backoff (default: 0.5)
      # @param max_delay [Float] Maximum delay cap in seconds (default: 10.0)
      # @yield The block to execute with retry protection
      # @return [Object] The return value of the block
      # @raise [StandardError] Re-raises the last error after all retries are exhausted
      def with_retry(max_retries: DEFAULT_MAX_RETRIES, base_delay: DEFAULT_BASE_DELAY,
                     max_delay: DEFAULT_MAX_DELAY)
        attempt = 0
        begin
          yield
        rescue *RETRYABLE_NETWORK_ERRORS, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
          attempt += 1
          raise if attempt > max_retries

          sleep(backoff_delay(attempt, base_delay, max_delay))
          retry
        rescue StandardError => e
          raise unless retryable_http_error?(e)

          attempt += 1
          raise if attempt > max_retries

          sleep(backoff_delay_for_http_error(e, attempt, base_delay, max_delay))
          retry
        end
      end

      private

      # Calculates exponential backoff delay with full jitter.
      #
      # Uses the "full jitter" algorithm: uniform random in [0, min(cap, base * 2^attempt)].
      # This decorrelates concurrent retries and avoids thundering herd on shared endpoints.
      #
      # @param attempt [Integer] Current retry attempt (1-based)
      # @param base_delay [Float] Base delay in seconds
      # @param max_delay [Float] Maximum delay cap in seconds
      # @return [Float] Randomized delay in seconds
      def backoff_delay(attempt, base_delay, max_delay)
        exp_delay = base_delay * (2**(attempt - 1))
        capped = [exp_delay, max_delay].min
        rand * capped
      end

      # Determines whether a StandardError represents a retryable HTTP error.
      #
      # Checks for HTTP 429 or 5xx status codes via the error's response object
      # or message text. Handles errors from openid_connect, rack-oauth2, and
      # other HTTP client libraries.
      #
      # @param error [StandardError] The caught exception
      # @return [Boolean] true if the error indicates a retryable HTTP condition
      def retryable_http_error?(error)
        status = extract_http_status(error)
        return RETRYABLE_HTTP_STATUSES.include?(status) if status

        msg = error.message
        msg.match?(/\b(429|5\d\d)\b/) ||
          msg.match?(/too many requests/i) ||
          msg.match?(/server error/i) ||
          msg.match?(/service unavailable/i) ||
          msg.match?(/bad gateway/i) ||
          msg.match?(/gateway timeout/i)
      end

      # Extracts an HTTP status code from an error object.
      #
      # Supports errors with a +status+ method (e.g. Rack::OAuth2 errors)
      # and errors with a +response+ object carrying a +status+ method.
      #
      # @param error [StandardError] The caught exception
      # @return [Integer, nil] The HTTP status code or nil if not extractable
      def extract_http_status(error)
        if error.respond_to?(:status)
          code = error.status.to_i
          return code if code.positive?
        end

        return unless error.respond_to?(:response) && error.response.respond_to?(:status)

        code = error.response.status.to_i
        code if code.positive?
      end

      # Calculates delay for HTTP errors, honoring Retry-After header when present.
      #
      # @param error [StandardError] The HTTP error
      # @param attempt [Integer] Current retry attempt (1-based)
      # @param base_delay [Float] Base delay in seconds
      # @param max_delay [Float] Maximum delay cap in seconds
      # @return [Float] Delay in seconds
      def backoff_delay_for_http_error(error, attempt, base_delay, max_delay)
        retry_after = extract_retry_after(error)
        calculated = backoff_delay(attempt, base_delay, max_delay)

        retry_after ? [retry_after, calculated].max : calculated
      end

      # Extracts a Retry-After value from an error's response headers.
      #
      # Supports both numeric (delay-seconds) and HTTP-date (RFC 7231 §7.1.3)
      # formats. Numeric values are returned directly (including values exceeding
      # max_delay). HTTP-date values are converted to seconds until the specified
      # time; past dates return nil.
      #
      # @param error [StandardError] The HTTP error
      # @return [Float, nil] Retry-After value in seconds or nil
      def extract_retry_after(error)
        return unless error.respond_to?(:response)

        resp = error.response
        header = resp['Retry-After'] if resp.respond_to?(:[])
        header ||= resp.headers['Retry-After'] if resp.respond_to?(:headers) && resp.headers.respond_to?(:[])
        return unless header

        # Try numeric (delay-seconds) first
        numeric = Float(header, exception: false)
        if numeric
          return numeric if numeric.finite? && numeric.positive?

          return nil
        end

        # Try HTTP-date format (e.g. "Thu, 18 Sep 2026 16:30:00 GMT")
        parse_retry_after_date(header)
      end

      # Parses an HTTP-date Retry-After header into seconds until the target time.
      #
      # @param header [String] The Retry-After header value in HTTP-date format
      # @return [Float, nil] Seconds until the specified time, or nil if invalid/past
      def parse_retry_after_date(header)
        target_time = Time.httpdate(header)
        seconds = (target_time - Time.now).to_f
        seconds.positive? ? seconds : nil
      rescue ArgumentError
        nil
      end
    end
  end
end
