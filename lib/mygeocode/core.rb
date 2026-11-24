# frozen_string_literal: true

require "json"
require "uri"

module MyGeocode
  # Request building, parameter encoding, answer parsing and the retry rules. Nothing here touches the network.
  module Core
    module_function

    # Drops nil and false, writes true as 1, joins lists with commas; extra is added last and wins.
    def encode_params(values, extra = nil)
      out = {}
      values.each do |name, value|
        next if value.nil? || value == false

        out[name.to_s] = join(value)
      end
      (extra || {}).each do |name, value|
        out[name.to_s] = join(value) unless value.nil?
      end
      out
    end

    def scalar(value)
      case value
      when true then "1"
      when false then "0"
      else value.to_s
      end
    end

    def join(value)
      value.is_a?(Array) ? value.map { |v| scalar(v) }.join(",") : scalar(value)
    end

    # [[lat, lon], ...] to "lat,lon|lat,lon"; a string (including "enc:...") passes through unchanged.
    def encode_points(points)
      return nil if points.nil?
      return points if points.is_a?(String)

      points.map { |p| "#{scalar(p[0])},#{scalar(p[1])}" }.join("|")
    end

    def pairs(points)
      points.map { |p| [p[0], p[1]] }
    end

    def build_url(base_url, path, params)
      url = "#{base_url}/#{path}"
      params.empty? ? url : "#{url}?#{URI.encode_www_form(params)}"
    end

    # The decoded JSON object and its meta, or raises ApiError / DecodeError.
    def parse_response(response, clock)
      meta = Meta.from_headers(response.headers)
      data = begin
        JSON.parse(response.body)
      rescue JSON::ParserError, EncodingError
        nil
      end
      if response.status >= 400 || (data.is_a?(Hash) && data["status"] == "error")
        raise api_error(response, data, meta, clock)
      end
      unless data.is_a?(Hash)
        raise DecodeError, "Expected a JSON object from the API, got HTTP #{response.status} with a body that is not one."
      end

      [data, meta]
    end

    def api_error(response, data, meta, clock)
      err = data.is_a?(Hash) && data["error"].is_a?(Hash) ? data["error"] : {}
      code = err["code"]
      message = err["message"]
      code = "http_error" if code.nil? || code == "" || code == false
      message = "HTTP #{response.status}" if message.nil? || message == "" || message == false
      param = err["param"].is_a?(String) ? err["param"] : nil
      ApiError.new(response.status, code.to_s, message.to_s, param, meta.request_id, server_wait(response, clock),
                   data.is_a?(Hash) ? data : nil)
    end

    # 1, 2, 4 ... seconds before the retry that follows failed try number attempt (counting from 0).
    def backoff(attempt)
      (2**attempt).to_f
    end

    # Seconds the server asks to wait: Retry-After, or on a 429 the time until X-Quota-Reset.
    def server_wait(response, clock)
      value = number(response.headers["Retry-After"])
      return [0.0, value].max unless value.nil?

      if response.status == 429
        reset = number(response.headers["X-Quota-Reset"])
        return [0.0, reset - clock.call].max unless reset.nil?
      end
      nil
    end

    # Seconds to wait before trying this request again, or nil to raise the error now.
    def retry_wait(max_retries, max_retry_wait, response, attempt, retried500, clock)
      return nil if attempt >= max_retries

      case response.status
      when 429
        wait = server_wait(response, clock)
        wait if !wait.nil? && wait <= max_retry_wait
      when 500
        retried500 ? nil : 1.0
      when 503
        wait = server_wait(response, clock)
        wait = backoff(attempt) if wait.nil?
        wait <= max_retry_wait ? wait : nil
      end
    end

    def number(value)
      return nil if value.nil?

      f = Float(value.to_s.strip)
      f.nan? || f.infinite? ? nil : f
    rescue ArgumentError
      nil
    end
  end
end
