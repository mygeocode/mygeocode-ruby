# frozen_string_literal: true

module Tests
  # Client behaviour: key handling, defaults, errors, retries, timeouts and the language rules.
  class ClientTest < Case
    def error_body(code, message = "x")
      { "status" => "error", "error" => { "code" => code, "message" => message } }
    end

    def test_keyless_sends_no_key_and_our_user_agent
      rec = Recorder.new(Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin")
      refute_key(rec.last.headers, "X-API-Key")
      assert_equal("mygeocode-ruby/#{MyGeocode::VERSION} (+https://www.mygeocode.com/sdks/)", rec.last.headers["User-Agent"])
      assert_equal(MyGeocode::USER_AGENT, rec.last.headers["User-Agent"])
      assert_equal("application/json", rec.last.headers["Accept"])
      assert(rec.last.url.start_with?("https://api.mygeocode.com/v1/forward?"), rec.last.url)
    end

    def test_key_goes_in_the_header_never_the_url
      rec = Recorder.new(Tests.replay("forward"))
      client(rec, key: "mg_test_key").forward("Brandenburg Gate, Berlin")
      assert_equal("mg_test_key", rec.last.headers["X-API-Key"])
      assert(!rec.last.url.include?("mg_test_key"))
      refute_key(rec.last.query, "key")
      assert(!client(rec, key: "mg_test_key").inspect.include?("mg_test_key"), "inspect shows the key")
    end

    def test_key_from_the_environment_and_empty_key_means_none
      ENV["MYGEOCODE_KEY"] = "mg_env_key"
      rec = Recorder.new(Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin")
      assert_equal("mg_env_key", rec.last.headers["X-API-Key"])
      client(rec, key: "").forward("Brandenburg Gate, Berlin")
      refute_key(rec.last.headers, "X-API-Key")
    end

    def test_defaults_are_ten_seconds_and_english
      rec = Recorder.new(Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin")
      assert_equal(10.0, rec.last.timeout)
      assert_equal("en", rec.last.query["lang"])
    end

    def test_base_url_and_timeout_reach_the_transport
      rec = Recorder.new(Tests.replay("forward"))
      client(rec, base_url: "https://example.test/v1/", timeout: 3).forward("Brandenburg Gate, Berlin")
      assert(rec.last.url.start_with?("https://example.test/v1/forward?"), rec.last.url)
      assert_equal(3.0, rec.last.timeout)
    end

    def test_lang_on_the_client_and_per_call
      rec = Recorder.new(Tests.replay("forward"))
      c = client(rec, lang: "de")
      c.forward("Brandenburg Gate, Berlin")
      assert_equal("de", rec.last.query["lang"])
      c.forward("Brandenburg Gate, Berlin", lang: "fr")
      assert_equal("fr", rec.last.query["lang"])
    end

    def test_timezone_language_only_when_chosen
      rec = Recorder.new(Tests.replay("timezone"))
      client(rec).timezone(35.6762, 139.6503)
      refute_key(rec.last.query, "language")
      client(rec).timezone(35.6762, 139.6503, lang: "ja")
      assert_equal("ja", rec.last.query["language"])
      client(rec).timezone(35.6762, 139.6503, language: "de")
      assert_equal("de", rec.last.query["language"])
      client(rec, lang: "en").timezone(35.6762, 139.6503)
      assert_equal("en", rec.last.query["language"])
      refute_key(rec.last.query, "lang")
    end

    def test_error_envelope_becomes_api_error
      rec = Recorder.new(Tests.replay("error_invalid_request"))
      error = assert_raises(MyGeocode::ApiError) { client(rec).forward("") }
      body = Tests.recording("error_invalid_request")
      assert_equal(body["status"], error.status)
      assert_equal(body["body"]["error"]["code"], error.code)
      assert_equal(body["body"]["error"]["message"], error.message)
      assert_equal(body["body"]["error"]["param"], error.param)
      assert_equal(body["headers"]["x-request-id"], error.request_id)
      assert_equal(body["body"], error.body)
      assert_nil(error.retry_after)
      assert(error.is_a?(MyGeocode::MyGeocodeError))
      assert_equal("invalid_request: #{error.message} (HTTP 400)", error.to_s)
    end

    def test_error_without_a_json_body
      rec = Recorder.new(Tests.answer(502, nil, {}, "<html>Bad gateway</html>"))
      error = assert_raises(MyGeocode::ApiError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_equal(502, error.status)
      assert_equal("http_error", error.code)
      assert_equal("HTTP 502", error.message)
      assert_nil(error.body)
    end

    def test_an_ok_answer_with_status_error_is_an_api_error
      rec = Recorder.new(Tests.answer(200, error_body("invalid_request")))
      error = assert_raises(MyGeocode::ApiError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_equal([200, "invalid_request"], [error.status, error.code])
    end

    def test_success_that_is_not_json_is_a_decode_error
      ["not json", "[1, 2]", ""].each do |text|
        rec = Recorder.new(Tests.answer(200, nil, {}, text))
        assert_raises(MyGeocode::DecodeError) { client(rec).forward("Brandenburg Gate, Berlin") }
      end
    end

    def test_429_waits_for_retry_after
      rec = Recorder.new(Tests.answer(429, error_body("rate_limited", "slow down"), "Retry-After" => "7"),
                         Tests.replay("forward"))
      result = client(rec).forward("Brandenburg Gate, Berlin")
      assert_equal([7.0], sleeps)
      assert_equal("ok", result.status)
      assert_equal(2, rec.sent.size)
    end

    def test_429_waits_until_the_quota_reset
      rec = Recorder.new(Tests.answer(429, error_body("quota_exceeded"), "X-Quota-Reset" => "1030"),
                         Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin")
      assert_equal([30.0], sleeps)
    end

    def test_quota_gone_for_the_day_raises_at_once
      rec = Recorder.new(Tests.answer(429, error_body("quota_exceeded"), "X-Quota-Reset" => "90000"))
      error = assert_raises(MyGeocode::ApiError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_equal("quota_exceeded", error.code)
      assert_equal(89_000.0, error.retry_after)
      assert_equal([], sleeps)
      assert_equal(1, rec.sent.size)
    end

    def test_429_without_any_wait_raises_at_once
      rec = Recorder.new(Tests.answer(429, error_body("rate_limited")))
      error = assert_raises(MyGeocode::ApiError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_nil(error.retry_after)
      assert_equal(1, rec.sent.size)
    end

    def test_max_retry_wait_is_configurable
      rec = Recorder.new(Tests.answer(429, error_body("rate_limited"), "Retry-After" => "90"), Tests.replay("forward"))
      client(rec, max_retry_wait: 120).forward("Brandenburg Gate, Berlin")
      assert_equal([90.0], sleeps)
    end

    def test_retries_stop_at_max_retries
      rec = Recorder.new(Tests.answer(503, error_body("unavailable")))
      assert_raises(MyGeocode::ApiError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_equal([1.0, 2.0], sleeps)
      assert_equal(3, rec.sent.size)
    end

    def test_max_retries_zero_never_retries
      rec = Recorder.new(Tests.answer(503, error_body("unavailable")))
      assert_raises(MyGeocode::ApiError) { client(rec, max_retries: 0).forward("Brandenburg Gate, Berlin") }
      assert_equal(1, rec.sent.size)
    end

    def test_503_uses_retry_after
      rec = Recorder.new(Tests.answer(503, error_body("maintenance"), "Retry-After" => "5"), Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin")
      assert_equal([5.0], sleeps)
    end

    def test_503_with_a_long_retry_after_raises
      rec = Recorder.new(Tests.answer(503, error_body("maintenance"), "Retry-After" => "900"))
      error = assert_raises(MyGeocode::ApiError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_equal(900.0, error.retry_after)
    end

    def test_500_is_retried_once_after_one_second
      broken = Tests.answer(500, error_body("server_error"))
      rec = Recorder.new(broken, Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin")
      assert_equal([1.0], sleeps)
      rec = Recorder.new(broken)
      sleeps.clear
      assert_raises(MyGeocode::ApiError) { client(rec, max_retries: 5).forward("Brandenburg Gate, Berlin") }
      assert_equal(2, rec.sent.size)
      assert_equal([1.0], sleeps)
    end

    def test_500_on_post_and_max_retries
      broken = Tests.answer(500, error_body("server_error"))
      rec = Recorder.new(broken, Tests.replay("forward_batch"))
      client(rec).forward_batch(["Brandenburg Gate, Berlin"])
      assert_equal(2, rec.sent.size)
      rec = Recorder.new(broken)
      assert_raises(MyGeocode::ApiError) { client(rec, max_retries: 0).forward_batch(["Brandenburg Gate, Berlin"]) }
      assert_equal(1, rec.sent.size)
    end

    def test_connection_errors_are_retried_on_get
      rec = Recorder.new(MyGeocode::NetworkError.new("refused"), MyGeocode::NetworkError.new("refused"),
                         Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin")
      assert_equal([1.0, 2.0], sleeps)
    end

    def test_network_error_after_the_retries
      rec = Recorder.new(MyGeocode::NetworkError.new("refused"))
      assert_raises(MyGeocode::NetworkError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_equal(3, rec.sent.size)
    end

    def test_timeouts_are_retried_then_raised
      rec = Recorder.new(MyGeocode::RequestTimeoutError.new("slow"))
      assert_raises(MyGeocode::RequestTimeoutError) { client(rec).forward("Brandenburg Gate, Berlin") }
      assert_equal(3, rec.sent.size)
    end

    def test_post_is_not_retried_after_a_connection_error
      rec = Recorder.new(MyGeocode::NetworkError.new("reset"), Tests.replay("forward_batch"))
      assert_raises(MyGeocode::NetworkError) { client(rec).forward_batch(["Brandenburg Gate, Berlin"]) }
      assert_equal(1, rec.sent.size)
    end

    def test_post_is_retried_on_429
      rec = Recorder.new(Tests.answer(429, error_body("rate_limited"), "Retry-After" => "2"),
                         Tests.replay("forward_batch"))
      client(rec).forward_batch(["Brandenburg Gate, Berlin"])
      assert_equal([2.0], sleeps)
    end

    def test_unknown_option_is_rejected
      assert_raises(ArgumentError) { client(Recorder.new(Tests.replay("forward"))).forward("x", limt: 1) }
    end
  end
end
