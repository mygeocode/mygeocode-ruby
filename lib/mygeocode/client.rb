# frozen_string_literal: true

require "json"

module MyGeocode
  # Client for the My Geocode API.
  #
  # Every option is optional. key defaults to the MYGEOCODE_KEY environment variable; with neither, no key is sent
  # and the network's free requests apply. lang defaults to English and is sent on every endpoint that takes it.
  # transport replaces the default Net::HTTP transport: anything with #call(HttpRequest) that returns an
  # HttpResponse. sleep and clock replace the retry wait and the clock (seconds since the epoch), for tests.
  #
  #   client = MyGeocode::Client.new
  #   client.forward("Brandenburg Gate, Berlin").results.first.formatted
  class Client
    DEFAULT_BASE_URL = "https://api.mygeocode.com/v1"

    attr_reader :base_url, :timeout, :max_retries, :max_retry_wait, :lang

    def initialize(key: nil, base_url: DEFAULT_BASE_URL, timeout: 10, max_retries: 2, max_retry_wait: 60, lang: nil,
                   transport: nil, sleep: nil, clock: nil)
      key = ENV["MYGEOCODE_KEY"] if key.nil?
      @key = key.nil? || key.to_s.strip.empty? ? nil : key.to_s.strip
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @timeout = Float(timeout)
      @max_retries = [0, Integer(max_retries)].max
      @max_retry_wait = Float(max_retry_wait)
      @lang_set = !lang.nil?
      @lang = lang.nil? ? "en" : lang
      @transport = transport || NetHttpTransport.new
      @sleep = sleep || ->(seconds) { Kernel.sleep(seconds) }
      @clock = clock || -> { Time.now.to_f }
    end

    def inspect
      "#<MyGeocode::Client base_url=#{@base_url.inspect} key=#{@key ? '[set]' : 'none'}>"
    end

    # Text, structured address fields or a place_id to coordinates.
    def forward(query = nil, street: nil, city: nil, state: nil, postcode: nil, country: nil, place_id: nil,
                limit: nil, countries: nil, bounds: nil, strict: false, proximity: nil, types: nil, lang: nil,
                annotations: false, timezone: false, elevation: false, wikidata: false, country_info: false,
                codes: false, sun: false, regions: false, districts: false, census: false, demographics: false,
                road: false, site: false, pretty: false, params: nil)
      values = {
        q: query, street: street, city: city, state: state, postcode: postcode, country: country,
        place_id: place_id, limit: limit, countries: countries, bounds: bounds, strict: strict,
        proximity: proximity, types: types, lang: lang_of(lang), annotations: annotations, timezone: timezone,
        elevation: elevation, wikidata: wikidata, country_info: country_info, codes: codes, sun: sun,
        regions: regions, districts: districts, census: census, demographics: demographics, road: road, site: site,
        pretty: pretty
      }
      get("forward", values, params, ForwardResponse)
    end

    # A point to the nearest address. result is nil when nothing is within radius.
    def reverse(lat, lon, level: nil, radius: nil, lang: nil, boundaries: false, annotations: false,
                timezone: false, elevation: false, wikidata: false, country_info: false, codes: false, sun: false,
                regions: false, districts: false, census: false, demographics: false, road: false, site: false,
                pretty: false, params: nil)
      values = {
        lat: lat, lon: lon, level: level, radius: radius, lang: lang_of(lang), boundaries: boundaries,
        annotations: annotations, timezone: timezone, elevation: elevation, wikidata: wikidata,
        country_info: country_info, codes: codes, sun: sun, regions: regions, districts: districts, census: census,
        demographics: demographics, road: road, site: site, pretty: pretty
      }
      get("reverse", values, params, ReverseResponse)
    end

    # Address suggestions for what someone has typed so far.
    def autocomplete(query, limit: nil, countries: nil, proximity: nil, bounds: nil, strict: false, types: nil,
                     lang: nil, pretty: false, params: nil)
      values = {
        q: query, limit: limit, countries: countries, proximity: proximity, bounds: bounds, strict: strict,
        types: types, lang: lang_of(lang), pretty: pretty
      }
      get("autocomplete", values, params, AutocompleteResponse)
    end

    # An IPv4 or IPv6 address; without one, the address the request came from.
    def ip(address = nil, elevation: false, pretty: false, params: nil)
      get("ip", { ip: address, elevation: elevation, pretty: pretty }, params, IpInfo)
    end

    # An IPv4 address; without one, the address the request came from.
    def ipv4(address = nil, elevation: false, pretty: false, params: nil)
      get("ipv4", { ip: address, elevation: elevation, pretty: pretty }, params, IpInfo)
    end

    # An IPv6 address; without one, the address the request came from.
    def ipv6(address = nil, elevation: false, pretty: false, params: nil)
      get("ipv6", { ip: address, elevation: elevation, pretty: pretty }, params, IpInfo)
    end

    # Zone, offset and local time for a point, or for a zone id with tz: (lat and lon left out).
    #
    # locations:, path: with samples:, or bounds: with rows: and cols: ask for several points at once; the answer
    # then also has them under raw["results"] (timezone_batch reads them for you).
    def timezone(lat = nil, lon = nil, tz: nil, timestamp: nil, lang: nil, language: nil, locations: nil, path: nil,
                 samples: nil, bounds: nil, rows: nil, cols: nil, pretty: false, params: nil)
      values = {
        lat: lat, lon: lon, tz: tz, timestamp: unix(timestamp), language: language_of(lang, language),
        locations: Core.encode_points(locations), path: Core.encode_points(path), samples: samples, bounds: bounds,
        rows: rows, cols: cols, pretty: pretty
      }
      get("timezone", values, params, TimezoneInfo)
    end

    # Height of a point, or of several points with locations:, a path: with samples:, or a grid.
    def elevation(lat = nil, lon = nil, locations: nil, path: nil, samples: nil, bounds: nil, rows: nil, cols: nil,
                  pretty: false, params: nil)
      values = {
        lat: lat, lon: lon, locations: Core.encode_points(locations), path: Core.encode_points(path),
        samples: samples, bounds: bounds, rows: rows, cols: cols, pretty: pretty
      }
      perform("GET", "elevation", Core.encode_params(values, params), nil, ElevationResponse)
    end

    # A postal code to every place that uses it. country (ISO alpha-2) narrows it to one country.
    def postcode(code, country: nil, pretty: false, params: nil)
      get("postcode", { code: code, country: country, pretty: pretty }, params, PostcodeResponse)
    end

    # Up to 100 searches in one request (each counts as one). The options apply to every search.
    def forward_batch(queries, limit: nil, countries: nil, bounds: nil, strict: false, proximity: nil, types: nil,
                      lang: nil, annotations: false, timezone: false, elevation: false, wikidata: false,
                      country_info: false, codes: false, sun: false, regions: false, districts: false, census: false,
                      demographics: false, road: false, site: false, pretty: false, params: nil)
      values = {
        limit: limit, countries: countries, bounds: bounds, strict: strict, proximity: proximity, types: types,
        lang: lang_of(lang), annotations: annotations, timezone: timezone, elevation: elevation,
        wikidata: wikidata, country_info: country_info, codes: codes, sun: sun, regions: regions,
        districts: districts, census: census, demographics: demographics, road: road, site: site, pretty: pretty
      }
      perform("POST", "forward", Core.encode_params(values, params), { "queries" => queries.to_a },
           ForwardBatchResponse)
    end

    # Up to 100 [lat, lon] points in one request (each counts as one). The options apply to every point.
    def reverse_batch(points, level: nil, radius: nil, lang: nil, boundaries: false, annotations: false,
                      timezone: false, elevation: false, wikidata: false, country_info: false, codes: false,
                      sun: false, regions: false, districts: false, census: false, demographics: false, road: false,
                      site: false, pretty: false, params: nil)
      values = {
        level: level, radius: radius, lang: lang_of(lang), boundaries: boundaries, annotations: annotations,
        timezone: timezone, elevation: elevation, wikidata: wikidata, country_info: country_info, codes: codes,
        sun: sun, regions: regions, districts: districts, census: census, demographics: demographics, road: road,
        site: site, pretty: pretty
      }
      perform("POST", "reverse", Core.encode_params(values, params), { "coords" => Core.pairs(points) },
           ReverseBatchResponse)
    end

    # Up to 100 addresses of either version in one request.
    def ip_batch(addresses, elevation: false, pretty: false, params: nil)
      get("ip", { ips: addresses.to_a.join(","), elevation: elevation, pretty: pretty }, params, IpBatchResponse)
    end

    # Up to 100 IPv4 addresses in one request.
    def ipv4_batch(addresses, elevation: false, pretty: false, params: nil)
      get("ipv4", { ips: addresses.to_a.join(","), elevation: elevation, pretty: pretty }, params, IpBatchResponse)
    end

    # Up to 100 IPv6 addresses in one request.
    def ipv6_batch(addresses, elevation: false, pretty: false, params: nil)
      get("ipv6", { ips: addresses.to_a.join(","), elevation: elevation, pretty: pretty }, params, IpBatchResponse)
    end

    # Timezones of up to 100 [lat, lon] points (or an "enc:" polyline string).
    def timezone_batch(points, timestamp: nil, lang: nil, language: nil, pretty: false, params: nil)
      values = {
        locations: Core.encode_points(points), timestamp: unix(timestamp), language: language_of(lang, language),
        pretty: pretty
      }
      get("timezone", values, params, TimezoneBatchResponse)
    end

    # Heights of up to 100 [lat, lon] points, sent as a POST body.
    def elevation_batch(points, pretty: false, params: nil)
      perform("POST", "elevation", Core.encode_params({ pretty: pretty }, params),
           { "locations" => Core.pairs(points) }, ElevationResponse)
    end

    private

    def lang_of(lang)
      lang.nil? ? @lang : lang
    end

    # Timezone's language: only when the caller chose one, here or on the client (the API answers English).
    def language_of(lang, language)
      chosen = lang.nil? ? language : lang
      return chosen unless chosen.nil?

      @lang_set ? @lang : nil
    end

    def unix(timestamp)
      timestamp.is_a?(Time) ? timestamp.to_i : timestamp
    end

    def now
      t = @clock.call
      t.to_f
    end

    def get(path, values, extra, model)
      perform("GET", path, Core.encode_params(values, extra), nil, model)
    end

    def perform(method, path, params, body, model)
      headers = { "User-Agent" => USER_AGENT, "Accept" => "application/json" }
      headers["X-API-Key"] = @key if @key
      data = nil
      unless body.nil?
        data = JSON.generate(body)
        headers["Content-Type"] = "application/json"
      end
      request = HttpRequest.new(method, Core.build_url(@base_url, path, params), headers, data, @timeout)
      clock = -> { now }
      attempt = 0
      retried500 = false
      loop do
        begin
          response = @transport.call(request)
        rescue NetworkError, RequestTimeoutError
          raise unless method == "GET" && attempt < @max_retries

          @sleep.call(Core.backoff(attempt))
          attempt += 1
          next
        end
        if [429, 500, 503].include?(response.status)
          wait = Core.retry_wait(@max_retries, @max_retry_wait, response, attempt, retried500, clock)
          unless wait.nil?
            retried500 ||= response.status == 500
            @sleep.call(wait)
            attempt += 1
            next
          end
        end
        answer, meta = Core.parse_response(response, clock)
        return build(model, answer, meta)
      end
    end

    def build(model, data, meta)
      if model == ElevationResponse && !data.key?("results") && data.key?("elevation_m")
        data = data.merge("results" => [data]) # a single point answered flat
      end
      model.from_hash(data, meta)
    end
  end
end
