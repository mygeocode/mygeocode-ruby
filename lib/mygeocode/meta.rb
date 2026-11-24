# frozen_string_literal: true

module MyGeocode
  # Figures from the response headers; nil when a header was not sent.
  class Meta
    attr_reader :request_id, :quota_limit, :quota_used, :quota_free_remaining, :quota_reset, :credits_remaining

    def initialize(request_id: nil, quota_limit: nil, quota_used: nil, quota_free_remaining: nil, quota_reset: nil,
                   credits_remaining: nil)
      @request_id = request_id
      @quota_limit = quota_limit
      @quota_used = quota_used
      @quota_free_remaining = quota_free_remaining
      @quota_reset = quota_reset
      @credits_remaining = credits_remaining
    end

    # Reads the figures from response headers (a Headers object or a Hash).
    def self.from_headers(headers)
      new(
        request_id: headers["X-Request-Id"],
        quota_limit: number(headers["X-Quota-Limit"]),
        quota_used: number(headers["X-Quota-Used"]),
        quota_free_remaining: number(headers["X-Quota-Free-Remaining"]),
        quota_reset: number(headers["X-Quota-Reset"]),
        credits_remaining: number(headers["X-Credits-Remaining"])
      )
    end

    def self.number(value)
      return nil if value.nil?

      Float(value.to_s.strip).to_i
    rescue ArgumentError, FloatDomainError
      nil
    end
    private_class_method :number

    def to_h
      {
        request_id: @request_id, quota_limit: @quota_limit, quota_used: @quota_used,
        quota_free_remaining: @quota_free_remaining, quota_reset: @quota_reset, credits_remaining: @credits_remaining
      }
    end

    def ==(other)
      other.is_a?(Meta) && other.to_h == to_h
    end

    def inspect
      "#<MyGeocode::Meta request_id=#{@request_id.inspect} quota_free_remaining=#{@quota_free_remaining.inspect}>"
    end
  end
end
