# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module MyGeocode
  # Response headers, read-only, names matched without regard to case.
  class Headers
    include Enumerable

    def initialize(items = {})
      @data = {}
      items.each { |name, value| @data[name.to_s.downcase] = value.to_s }
    end

    def [](name)
      @data[name.to_s.downcase]
    end

    def key?(name)
      @data.key?(name.to_s.downcase)
    end

    def each(&block)
      @data.each(&block)
    end

    def to_h
      @data.dup
    end
  end

  # What the client asks a transport to send. method is "GET" or "POST"; body is a JSON string or nil; timeout is in
  # seconds.
  class HttpRequest
    attr_reader :method, :url, :headers, :body, :timeout

    def initialize(method, url, headers, body, timeout)
      @method = method
      @url = url
      @headers = headers
      @body = body
      @timeout = timeout
    end

    def inspect
      "#<MyGeocode::HttpRequest #{@method} #{@url}>"
    end
  end

  # What a transport returns. Any HTTP status is a response; only a failure to get one raises.
  class HttpResponse
    attr_reader :status, :headers, :body

    def initialize(status, headers = {}, body = "")
      @status = Integer(status)
      @headers = headers.is_a?(Headers) ? headers : Headers.new(headers)
      @body = body.to_s
    end

    def inspect
      "#<MyGeocode::HttpResponse #{@status}>"
    end
  end

  # The default transport: Net::HTTP with the system's certificate store, one connection per request. It raises
  # RequestTimeoutError or NetworkError when no answer arrives; any HTTP status is returned.
  class NetHttpTransport
    TIMEOUTS = [Timeout::Error].freeze
    FAILURES = [SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError].freeze

    def call(request)
      uri = URI.parse(request.url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = request.timeout
      http.read_timeout = request.timeout
      http.ssl_timeout = request.timeout if http.use_ssl?
      http.write_timeout = request.timeout if http.respond_to?(:write_timeout=) # Ruby 2.6 and newer
      response = http.start { |connection| connection.request(build(request, uri)) }
      headers = {}
      response.each_header { |name, value| headers[name] = value }
      body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      HttpResponse.new(response.code.to_i, Headers.new(headers), body)
    rescue *TIMEOUTS
      raise RequestTimeoutError, "Request timed out after #{request.timeout} s"
    rescue *FAILURES => e
      raise NetworkError, "Network error: #{e.class}: #{e.message}"
    end

    private

    def build(request, uri)
      klass = request.method == "POST" ? Net::HTTP::Post : Net::HTTP::Get
      http_request = klass.new(uri.request_uri)
      request.headers.each { |name, value| http_request[name] = value }
      http_request.body = request.body if request.body
      http_request
    end
  end
end
