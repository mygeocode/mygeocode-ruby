# frozen_string_literal: true

module MyGeocode
  # Base class of every error this library raises.
  class MyGeocodeError < StandardError
  end

  # The API answered with an error.
  #
  # status is the HTTP status, code the API's error code (such as "invalid_request"; "http_error" when the answer had
  # none), message its explanation ("HTTP <status>" when the answer had none), param the parameter at fault,
  # request_id the X-Request-Id header and retry_after the seconds the API asked to wait (Retry-After, or the time to
  # X-Quota-Reset on a 429), or nil. body is the decoded error answer, or nil when it was not a JSON object.
  class ApiError < MyGeocodeError
    attr_reader :status, :code, :param, :request_id, :retry_after, :body

    def initialize(status, code, message, param = nil, request_id = nil, retry_after = nil, body = nil)
      super("#{code}: #{message} (HTTP #{status})")
      @status = status
      @code = code
      @api_message = message
      @param = param
      @request_id = request_id
      @retry_after = retry_after
      @body = body
    end

    # The API's explanation, without the code and status that #to_s adds.
    def message
      @api_message
    end

    def to_s
      "#{@code}: #{@api_message} (HTTP #{@status})"
    end
  end

  # No answer within the timeout.
  class RequestTimeoutError < MyGeocodeError
  end

  # The connection failed: DNS, refused, reset or TLS.
  class NetworkError < MyGeocodeError
  end

  # The answer could not be read as a JSON object.
  class DecodeError < MyGeocodeError
  end
end
