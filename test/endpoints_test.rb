# frozen_string_literal: true

module Tests
  # Every method sends the shared example values, the request must equal the recorded one, and the answer must be
  # read into the right objects (the recordings in test/fixtures are real answers of the API).
  class EndpointsTest < Case
    def test_forward
      rec = Recorder.new(Tests.replay("forward"))
      r = client(rec).forward("Brandenburg Gate, Berlin")
      assert_sent_like("forward", rec.last)
      want = Tests.recording("forward")["body"]["results"][0]
      assert_equal("ok", r.status)
      assert_instance_of(MyGeocode::Place, r.results[0])
      assert_equal("Brandenburg Gate, State of Berlin, Germany", r.results[0].formatted)
      assert_equal(want["lat"], r.results[0].lat)
      assert_equal(want["lon"], r.results[0].lon)
      assert_equal(want["components"]["country_code"], r.results[0].components.country_code)
      assert_equal(Tests.recording("forward")["body"], r.raw)
      assert_equal(r.raw, r.to_h)
    end

    def test_forward_meta_comes_from_the_headers
      rec = Recorder.new(Tests.replay("forward"))
      r = client(rec).forward("Brandenburg Gate, Berlin")
      headers = Tests.recording("forward")["headers"]
      assert_equal(headers["x-request-id"], r.meta.request_id)
      assert_equal(Integer(headers["x-quota-limit"]), r.meta.quota_limit)
      assert_equal(Integer(headers["x-quota-used"]), r.meta.quota_used)
      assert_equal(Integer(headers["x-quota-free-remaining"]), r.meta.quota_free_remaining)
      assert_equal(Integer(headers["x-quota-reset"]), r.meta.quota_reset)
      assert_nil(r.meta.credits_remaining)
    end

    def test_forward_structured
      rec = Recorder.new(Tests.replay("forward_structured"))
      r = client(rec).forward(street: "10 Downing Street", city: "London", country: "GB")
      assert_sent_like("forward_structured", rec.last)
      assert_equal("Downing Street, London SW1A, United Kingdom", r.results[0].formatted)
    end

    def test_reverse
      rec = Recorder.new(Tests.replay("reverse"))
      r = client(rec).reverse(*EIFFEL)
      assert_sent_like("reverse", rec.last)
      assert_equal("5 Avenue Anatole France, 75007 Paris, France", r.result.formatted)
      assert_equal(47, r.result.distance_m)
    end

    def test_autocomplete
      rec = Recorder.new(Tests.replay("autocomplete"))
      r = client(rec).autocomplete("1600 Pennsylvania")
      assert_sent_like("autocomplete", rec.last)
      assert_equal("1600 Pennsylvania Avenue NW, Washington, DC 20500, United States", r.suggestions[0].text)
    end

    def test_ip_ipv4_ipv6
      [%w[ip ip 8.8.8.8], %w[ipv4 ipv4 8.8.8.8], %w[ipv6 ipv6 2001:4860:4860::8888]].each do |method, name, address|
        rec = Recorder.new(Tests.replay(name))
        r = client(rec).send(method, address)
        assert_sent_like(name, rec.last)
        assert_instance_of(MyGeocode::IpInfo, r)
        assert_equal(address, r.ip)
        assert_equal("Google LLC", r.as_name)
      end
      r = client(Recorder.new(Tests.replay("ip"))).ip("8.8.8.8")
      assert_equal(["United States", "Mountain View", 15_169, true], [r.country, r.city, r.asn, r.is_datacenter])
    end

    def test_ip_of_the_caller_sends_no_address
      rec = Recorder.new(Tests.replay("ip"))
      client(rec).ip
      refute_key(rec.last.query, "ip")
      assert_equal("/v1/ip", rec.last.path)
    end

    def test_timezone
      rec = Recorder.new(Tests.replay("timezone"))
      r = client(rec).timezone(35.6762, 139.6503)
      assert_sent_like("timezone", rec.last)
      assert_equal(["Asia/Tokyo", "+09:00", "Japan Standard Time", "JST"], [r.timezone, r.utc_offset, r.name, r.abbreviation])
    end

    def test_timezone_by_zone_id
      rec = Recorder.new(Tests.replay("timezone_tz"))
      r = client(rec).timezone(tz: "Europe/Paris")
      assert_sent_like("timezone_tz", rec.last)
      assert_equal("Europe/Paris", r.timezone)
    end

    def test_elevation
      rec = Recorder.new(Tests.replay("elevation"))
      r = client(rec).elevation(27.9881, 86.9250)
      assert_sent_like("elevation", rec.last)
      assert_instance_of(MyGeocode::ElevationPoint, r.results[0])
      assert_equal(8627.0, r.results[0].elevation_m)
    end

    def test_elevation_answered_flat_is_read_as_a_list_of_one
      flat = { "status" => "ok", "lat" => 27.9881, "lon" => 86.925, "elevation_m" => 8627, "resolution_m" => 30 }
      r = client(Recorder.new(Tests.answer(200, flat))).elevation(27.9881, 86.9250)
      assert_equal(1, r.results.size)
      assert_equal([8627, 30], [r.results[0].elevation_m, r.results[0].resolution_m])
    end

    def test_postcode
      rec = Recorder.new(Tests.replay("postcode"))
      r = client(rec).postcode("10001", country: "US")
      assert_sent_like("postcode", rec.last)
      assert_instance_of(MyGeocode::PostcodePlace, r.results[0])
      assert_equal(["New York", "NY"], [r.results[0].place, r.results[0].region_code])
    end

    def test_forward_batch
      rec = Recorder.new(Tests.replay("forward_batch"))
      r = client(rec).forward_batch(["Brandenburg Gate, Berlin", "Sydney Opera House", "Statue of Liberty, New York"])
      assert_sent_like("forward_batch", rec.last)
      assert_instance_of(MyGeocode::ForwardBatchEntry, r.results[0])
      assert_equal(
        [
          ["Brandenburg Gate, Berlin", "Brandenburg Gate, State of Berlin, Germany"],
          ["Sydney Opera House", "Sydney Opera House, Sydney, New South Wales, Australia"],
          ["Statue of Liberty, New York", "Statue of Liberty, New York, New York, United States"]
        ],
        r.results.map { |e| [e.query, e.results[0].formatted] }
      )
    end

    def test_forward_batch_reads_a_numeric_postcode_as_text
      rec = Recorder.new(Tests.replay("forward_batch"))
      r = client(rec).forward_batch(["Brandenburg Gate, Berlin", "Sydney Opera House", "Statue of Liberty, New York"])
      york = r.results[2].results[3]
      assert_equal(68_467, york.raw["components"]["postcode"])
      assert_equal("68467", york.components.postcode)
    end

    def test_reverse_batch
      rec = Recorder.new(Tests.replay("reverse_batch"))
      r = client(rec).reverse_batch([EIFFEL, LIBERTY, OPERA])
      assert_sent_like("reverse_batch", rec.last)
      assert_instance_of(MyGeocode::ReverseResponse, r.results[0])
      assert_equal(
        ["5 Avenue Anatole France, 75007 Paris, France", "1 Liberty Island, New York, NY 10004, United States",
         "2B Macquarie Street, Sydney NSW 2000, Australia"],
        r.results.map { |p| p.result.formatted }
      )
    end

    def test_ip_batches
      [
        ["ip_batch", ["8.8.8.8", "2606:4700:4700::1111"]],
        ["ipv4_batch", ["8.8.8.8", "1.1.1.1", "9.9.9.9"]],
        ["ipv6_batch", ["2001:4860:4860::8888", "2606:4700:4700::1111"]]
      ].each do |name, addresses|
        rec = Recorder.new(Tests.replay(name))
        r = client(rec).send(name, addresses)
        assert_sent_like(name, rec.last)
        assert_equal(addresses, r.results.map(&:ip))
      end
      r = client(Recorder.new(Tests.replay("ipv4_batch"))).ipv4_batch(["8.8.8.8", "1.1.1.1", "9.9.9.9"])
      assert_equal(["Google LLC", "Cloudflare, Inc.", "Quad9"], r.results.map(&:as_name))
    end

    def test_ip_batch_entry_the_api_rejects
      bad = { "status" => "error", "ip" => "not-an-ip", "error" => { "code" => "invalid_ip", "message" => "Not an IP address." } }
      body = { "status" => "ok", "results" => [Tests.recording("ipv4")["body"], bad] }
      r = client(Recorder.new(Tests.answer(200, body))).ip_batch(["8.8.8.8", "not-an-ip"])
      assert_equal("ok", r.results[0].status)
      assert_equal("error", r.results[1].status)
      assert_equal("invalid_ip", r.results[1].error["code"])
    end

    def test_timezone_batch
      rec = Recorder.new(Tests.replay("timezone_batch"))
      r = client(rec).timezone_batch([EIFFEL, LIBERTY, OPERA])
      assert_sent_like("timezone_batch", rec.last)
      assert_instance_of(MyGeocode::TimezoneInfo, r.results[0])
      assert_equal(["Europe/Paris", "America/New_York", "Australia/Sydney"], r.results.map(&:timezone))
      assert_equal(Tests.recording("timezone_batch")["body"]["timestamp"], r.timestamp)
    end

    def test_elevation_batch
      rec = Recorder.new(Tests.replay("elevation_batch"))
      r = client(rec).elevation_batch([EIFFEL, LIBERTY, OPERA])
      assert_sent_like("elevation_batch", rec.last)
      assert_equal([37.0, 0.0, 10.0], r.results.map(&:elevation_m))
    end

    def test_unknown_fields_do_not_break_parsing
      body = Tests.recording("reverse")["body"].merge("brand_new_field" => { "x" => 1 })
      body["result"] = body["result"].merge("another_new_field" => [1, 2])
      r = client(Recorder.new(Tests.answer(200, body))).reverse(*EIFFEL)
      assert_equal({ "x" => 1 }, r.raw["brand_new_field"])
      assert_equal([1, 2], r.result.raw["another_new_field"])
      assert_equal("5 Avenue Anatole France, 75007 Paris, France", r.result.formatted)
    end
  end
end
