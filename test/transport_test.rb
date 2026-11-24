# frozen_string_literal: true

require "socket"

module Tests
  # The Net::HTTP transport against a small local HTTP server (no internet). The server is a plain TCPServer, so the
  # test needs nothing outside the standard library on any Ruby.
  class TransportTest < Case
    def start_server
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      thread = Thread.new do
        loop do
          socket = begin
            server.accept
          rescue IOError, SystemCallError
            break
          end
          Thread.new(socket) { |s| serve(s) }
        end
      end
      [server, thread, "http://127.0.0.1:#{port}/v1"]
    end

    def serve(socket)
      request_line = socket.gets.to_s
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      length = headers["content-length"].to_i
      body = length > 0 ? socket.read(length) : nil
      method, path = request_line.split(" ")
      sleep 1.5 if path.start_with?("/v1/slow")
      status = 200
      extra = { "X-Request-Id" => "local-1", "X-Quota-Limit" => "2500" }
      out = {
        "status" => "ok", "method" => method, "path" => path, "ua" => headers["user-agent"],
        "key" => headers["x-api-key"], "content_type" => headers["content-type"], "body" => body, "query" => nil,
        "results" => []
      }
      if path.start_with?("/v1/limited")
        status = 429
        extra = { "Retry-After" => "1" }
        out = { "status" => "error", "error" => { "code" => "rate_limited", "message" => "Slow down." } }
      end
      data = JSON.generate(out)
      socket.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{data.bytesize}\r\n")
      extra.each { |k, v| socket.write("#{k}: #{v}\r\n") }
      socket.write("Connection: close\r\n\r\n#{data}")
    rescue IOError, SystemCallError
      nil
    ensure
      socket.close unless socket.closed?
    end

    def with_server
      server, thread, url = start_server
      yield url
    ensure
      server.close
      thread.join
    end

    def test_get_over_the_real_transport
      with_server do |url|
        r = MyGeocode::Client.new(base_url: url, key: "mg_local").forward("Brandenburg Gate, Berlin")
        assert_equal("GET", r.raw["method"])
        assert_equal("mg_local", r.raw["key"])
        assert(r.raw["ua"].start_with?("mygeocode-ruby/"), r.raw["ua"])
        assert(r.raw["path"].start_with?("/v1/forward?") && r.raw["path"].include?("lang=en"), r.raw["path"])
        assert_equal(["local-1", 2500], [r.meta.request_id, r.meta.quota_limit])
      end
    end

    def test_post_over_the_real_transport
      with_server do |url|
        r = MyGeocode::Client.new(base_url: url).elevation_batch([EIFFEL])
        assert_equal(["POST", "application/json", '{"locations":[[48.8584,2.2945]]}'],
                     [r.raw["method"], r.raw["content_type"], r.raw["body"]])
      end
    end

    def test_timeout_over_the_real_transport
      with_server do |url|
        transport = MyGeocode::NetHttpTransport.new
        request = MyGeocode::HttpRequest.new("GET", "#{url}/slow", {}, nil, 0.3)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        assert_raises(MyGeocode::RequestTimeoutError) { transport.call(request) }
        assert(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 1.4, "the timeout did not stop the request")
      end
    end

    def test_429_over_the_real_transport
      with_server do |url|
        transport = MyGeocode::NetHttpTransport.new
        response = transport.call(MyGeocode::HttpRequest.new("GET", "#{url}/limited", {}, nil, 5))
        assert_equal([429, "1"], [response.status, response.headers["retry-after"]])
        error = assert_raises(MyGeocode::ApiError) { MyGeocode::Core.parse_response(response, -> { 0.0 }) }
        assert_equal(["rate_limited", 1.0], [error.code, error.retry_after])
      end
    end

    def test_connection_refused_is_a_network_error
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close
      slept = []
      c = MyGeocode::Client.new(base_url: "http://127.0.0.1:#{port}/v1", sleep: ->(s) { slept << s })
      assert_raises(MyGeocode::NetworkError) { c.reverse(*EIFFEL) }
      assert_equal([1.0, 2.0], slept)
    end
  end
end
