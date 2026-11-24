# frozen_string_literal: true

module Tests
  # Every documented parameter is a keyword argument, sent under the API's own name.
  class ParametersTest < Case
    FLAGS = %w[timezone elevation wikidata country_info codes sun regions districts census demographics road site
               annotations].freeze

    def test_forward_every_parameter
      rec = Recorder.new(Tests.replay("forward"))
      client(rec).forward(
        "Brandenburg Gate, Berlin", street: "Pariser Platz", city: "Berlin", state: "Berlin", postcode: "10117",
        country: "DE", place_id: "abc", limit: 3, countries: %w[de at], bounds: [52.3, 13.0, 52.7, 13.8],
        strict: true, proximity: [52.5, 13.4], types: %w[poi address], lang: "de", annotations: true, pretty: true
      )
      assert_equal({
                     "q" => "Brandenburg Gate, Berlin", "street" => "Pariser Platz", "city" => "Berlin",
                     "state" => "Berlin", "postcode" => "10117", "country" => "DE", "place_id" => "abc",
                     "limit" => "3", "countries" => "de,at", "bounds" => "52.3,13.0,52.7,13.8", "strict" => "1",
                     "proximity" => "52.5,13.4", "types" => "poi,address", "lang" => "de", "annotations" => "1",
                     "pretty" => "1"
                   }, rec.last.query)
    end

    def test_flags_on_forward_reverse_and_their_batches
      FLAGS.each do |flag|
        rec = Recorder.new(Tests.replay("forward"))
        c = client(rec)
        options = { flag.to_sym => true }
        c.forward("Brandenburg Gate, Berlin", **options)
        assert_equal("1", rec.last.query[flag], flag)
        c.reverse(*EIFFEL, **options)
        assert_equal("1", rec.last.query[flag], flag)
        c.forward_batch(["Brandenburg Gate, Berlin"], **options)
        assert_equal("1", rec.last.query[flag], flag)
        c.reverse_batch([EIFFEL], **options)
        assert_equal("1", rec.last.query[flag], flag)
        c.forward("Brandenburg Gate, Berlin", flag.to_sym => false)
        refute_key(rec.last.query, flag)
      end
    end

    def test_reverse_every_parameter
      rec = Recorder.new(Tests.replay("reverse"))
      client(rec).reverse(*EIFFEL, level: "city", radius: 500, lang: "fr", boundaries: true, annotations: true,
                                   pretty: true)
      assert_equal({
                     "lat" => "48.8584", "lon" => "2.2945", "level" => "city", "radius" => "500", "lang" => "fr",
                     "boundaries" => "1", "annotations" => "1", "pretty" => "1"
                   }, rec.last.query)
    end

    def test_autocomplete_every_parameter
      rec = Recorder.new(Tests.replay("autocomplete"))
      client(rec).autocomplete("1600 Pennsylvania", limit: 5, countries: "us", proximity: [38.9, -77.0],
                                                    bounds: "38,-78,39,-76", strict: true, types: "address",
                                                    lang: "en", pretty: true)
      assert_equal({
                     "q" => "1600 Pennsylvania", "limit" => "5", "countries" => "us", "proximity" => "38.9,-77.0",
                     "bounds" => "38,-78,39,-76", "strict" => "1", "types" => "address", "lang" => "en",
                     "pretty" => "1"
                   }, rec.last.query)
    end

    def test_ip_parameters
      rec = Recorder.new(Tests.replay("ip"))
      c = client(rec)
      c.ipv4("8.8.8.8", elevation: true, pretty: true)
      assert_equal({ "ip" => "8.8.8.8", "elevation" => "1", "pretty" => "1" }, rec.last.query)
      c.ipv6_batch(["2001:4860:4860::8888", "2606:4700:4700::1111"], elevation: true)
      assert_equal({ "ips" => "2001:4860:4860::8888,2606:4700:4700::1111", "elevation" => "1" }, rec.last.query)
    end

    def test_timezone_parameters
      rec = Recorder.new(Tests.replay("timezone"))
      c = client(rec)
      c.timezone(35.6762, 139.6503, timestamp: 1_767_225_600, lang: "ja", pretty: true)
      assert_equal({ "lat" => "35.6762", "lon" => "139.6503", "timestamp" => "1767225600", "language" => "ja",
                     "pretty" => "1" }, rec.last.query)
      c.timezone(35.6762, 139.6503, timestamp: Time.at(1_767_225_600))
      assert_equal("1767225600", rec.last.query["timestamp"])
      c.timezone(locations: [EIFFEL, LIBERTY])
      assert_equal({ "locations" => "48.8584,2.2945|40.6892,-74.0445" }, rec.last.query)
      c.timezone(path: "enc:abc", samples: 10)
      assert_equal({ "path" => "enc:abc", "samples" => "10" }, rec.last.query)
      c.timezone(bounds: [40, -75, 41, -73], rows: 3, cols: 4)
      assert_equal({ "bounds" => "40,-75,41,-73", "rows" => "3", "cols" => "4" }, rec.last.query)
      c.timezone_batch([EIFFEL], timestamp: 1_767_225_600, lang: "de")
      assert_equal({ "locations" => "48.8584,2.2945", "timestamp" => "1767225600", "language" => "de" },
                   rec.last.query)
      c.timezone_batch("enc:_p~iF~ps|U", language: "fr", pretty: true)
      assert_equal({ "locations" => "enc:_p~iF~ps|U", "language" => "fr", "pretty" => "1" }, rec.last.query)
    end

    def test_elevation_parameters
      rec = Recorder.new(Tests.replay("elevation"))
      c = client(rec)
      c.elevation(locations: [EIFFEL, LIBERTY], pretty: true)
      assert_equal({ "locations" => "48.8584,2.2945|40.6892,-74.0445", "pretty" => "1" }, rec.last.query)
      c.elevation(path: [EIFFEL, LIBERTY], samples: 5)
      assert_equal({ "path" => "48.8584,2.2945|40.6892,-74.0445", "samples" => "5" }, rec.last.query)
      c.elevation(bounds: [27, 86, 28, 87], rows: 2, cols: 2)
      assert_equal({ "bounds" => "27,86,28,87", "rows" => "2", "cols" => "2" }, rec.last.query)
    end

    def test_postcode_parameters
      rec = Recorder.new(Tests.replay("postcode"))
      client(rec).postcode("75008", country: "FR", pretty: true)
      assert_equal({ "code" => "75008", "country" => "FR", "pretty" => "1" }, rec.last.query)
    end

    def test_batch_options_go_in_the_query_string
      rec = Recorder.new(Tests.replay("forward_batch"))
      c = client(rec)
      c.forward_batch(["Brandenburg Gate, Berlin"], limit: 1, countries: ["de"], bounds: "52,13,53,14", strict: true,
                                                    proximity: [52.5, 13.4], types: "poi", lang: "fr",
                                                    annotations: true)
      assert_equal({ "queries" => ["Brandenburg Gate, Berlin"] }, rec.last.json)
      assert_equal({
                     "limit" => "1", "countries" => "de", "bounds" => "52,13,53,14", "strict" => "1",
                     "proximity" => "52.5,13.4", "types" => "poi", "lang" => "fr", "annotations" => "1"
                   }, rec.last.query)
      assert_equal("application/json", rec.last.headers["Content-Type"])
      c.reverse_batch([EIFFEL], level: "street", radius: 100, boundaries: true)
      assert_equal({ "coords" => [[48.8584, 2.2945]] }, rec.last.json)
      assert_equal({ "level" => "street", "radius" => "100", "lang" => "en", "boundaries" => "1" }, rec.last.query)
      c.elevation_batch([EIFFEL], pretty: true)
      assert_equal({ "locations" => [[48.8584, 2.2945]] }, rec.last.json)
      assert_equal({ "pretty" => "1" }, rec.last.query)
    end

    def test_params_pass_through_and_win
      rec = Recorder.new(Tests.replay("forward"))
      client(rec).forward("Brandenburg Gate, Berlin", limit: 2, params: { "limit" => 5, brand_new: "x", "skip" => nil })
      assert_equal("5", rec.last.query["limit"])
      assert_equal("x", rec.last.query["brand_new"])
      refute_key(rec.last.query, "skip")
    end
  end
end
