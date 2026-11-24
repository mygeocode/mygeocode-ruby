# My Geocode Ruby SDK

The official Ruby client for the [My Geocode API](https://www.mygeocode.com/): forward and reverse geocoding, address
autocomplete, IPv4 and IPv6 lookup, timezones, elevation and postal codes.

![Ruby 2.4 and newer](https://img.shields.io/badge/ruby-2.4%20and%20newer-cc342d)
![Dependencies: none](https://img.shields.io/badge/dependencies-none-brightgreen)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

- Standard library only: `Net::HTTP` and `json`, no other gems.
- Works on Ruby 2.4 and newer, with no warnings, not even with `-w`.
- Nothing global: no monkey patches, no logger, no changes to the environment.
- 2,500 free requests a day without a key or an account.

## Install

```bash
gem install mygeocode
```

or in your `Gemfile`:

```ruby
gem "mygeocode"
```

## Quick start (no key)

```ruby
require "mygeocode"

client = MyGeocode::Client.new

place = client.forward("Brandenburg Gate, Berlin").results[0]
puts place.formatted                # Brandenburg Gate, State of Berlin, Germany
puts "#{place.lat} #{place.lon}"    # 52.516268 13.377692

address = client.reverse(48.8584, 2.2945)
puts address.result.formatted       # 5 Avenue Anatole France, 75007 Paris, France
```

Without a key, each network gets 2,500 free requests a day. `meta.quota_free_remaining` on any answer tells you how
many are left. Make one client and share it: it holds no connection between calls, so it is safe to use from many
threads.

## Using a key

A key adds your account's prepaid credit or Unlimited package on top of the free requests. Create one in the
[dashboard](https://www.mygeocode.com/dashboard).

```ruby
client = MyGeocode::Client.new(key: "YOUR_KEY")
```

If you leave out `key`, the client reads the `MYGEOCODE_KEY` environment variable. Pass `key: ""` to make sure no
key is sent. The key always travels in the `X-API-Key` header, never in the URL, the SDK never writes it anywhere, and
`client.inspect` hides it.

## Language

Results are in English unless you set `lang`. Set it once on the client, or per call:

```ruby
client = MyGeocode::Client.new(lang: "de")

client.reverse(48.8584, 2.2945, lang: "fr") # this call only
```

`lang` takes an ISO 639-1 code such as `de`, `ja` or `pt-BR`. The whole address comes back in that language and
script. On its own, the API answers each result in the language of its area; the SDK sends `lang=en` by default so
that every result reads the same.

## Methods

Every method takes its main arguments first, then keyword options named after the API's own parameters. A keyword
the method does not know raises `ArgumentError`. Every method also takes:

- `params:` a Hash of more query parameters, sent as they are (and winning over the named options), so a parameter the
  API adds later works before the SDK knows it.
- `pretty: true` for indented JSON.

Points are `[lat, lon]` arrays. `countries` and `types` take an Array or a comma-separated String; `bounds` takes
`[south, west, north, east]` or the API's own String.

| Method | Endpoint |
|---|---|
| [`forward`](#forward) | `GET /v1/forward` |
| [`reverse`](#reverse) | `GET /v1/reverse` |
| [`autocomplete`](#autocomplete) | `GET /v1/autocomplete` |
| [`ip`, `ipv4`, `ipv6`](#ip-ipv4-ipv6) | `GET /v1/ip`, `/v1/ipv4`, `/v1/ipv6` |
| [`timezone`](#timezone) | `GET /v1/timezone` |
| [`elevation`](#elevation) | `GET /v1/elevation` |
| [`postcode`](#postcode) | `GET /v1/postcode` |
| [`forward_batch`](#forward_batch) | `POST /v1/forward` |
| [`reverse_batch`](#reverse_batch) | `POST /v1/reverse` |
| [`ip_batch`, `ipv4_batch`, `ipv6_batch`](#ip_batch-ipv4_batch-ipv6_batch) | `GET /v1/ip`, `/v1/ipv4`, `/v1/ipv6` with `ips` |
| [`timezone_batch`](#timezone_batch) | `GET /v1/timezone` with `locations` |
| [`elevation_batch`](#elevation_batch) | `POST /v1/elevation` |

### forward

Text, structured address fields or a place id to coordinates. Returns a `ForwardResponse` whose `results` holds up to
`limit` `Place` objects, best first. An empty list means nothing matched.

```ruby
found = client.forward("Brandenburg Gate, Berlin")
puts found.results[0].formatted # Brandenburg Gate, State of Berlin, Germany

client.forward("Brandenburg Gate, Berlin", limit: 3, countries: ["de"])
client.forward(street: "10 Downing Street", city: "London", country: "GB")
```

| Option | What it does |
|---|---|
| `street:`, `city:`, `state:`, `postcode:`, `country:` | Structured search instead of (or as well as) free text. Leave out the query to search by these alone. |
| `place_id:` | Look up a `place_id` from an earlier result. |
| `limit:` | 1 to 10 results. |
| `countries:` | ISO 3166-1 alpha-2 codes to search in, such as `["de", "at"]` or `"de,at"`. |
| `bounds:` | A box that results should fall in: `[south, west, north, east]`. |
| `strict:` | Only return results inside `bounds`. |
| `proximity:` | Prefer results near this point: `[lat, lon]`. |
| `types:` | Kinds of result to keep, such as `address` or `poi`. |
| `lang:` | Language of the result. |
| `timezone:`, `elevation:`, `wikidata:`, `country_info:`, `codes:`, `sun:`, `regions:`, `districts:`, `census:`, `demographics:`, `road:`, `site:` | Each adds its extra block to every result. |
| `annotations:` | Adds every extra block at once. |

### reverse

A point to the nearest address. Returns a `ReverseResponse` whose `result` is a `Place`, or `nil` when nothing is in
range.

```ruby
place = client.reverse(48.8584, 2.2945).result
puts place.formatted  # 5 Avenue Anatole France, 75007 Paris, France
puts place.distance_m # 47 (metres from the point you gave)

client.reverse(48.8584, 2.2945, level: "city", timezone: true)
```

| Option | What it does |
|---|---|
| `level:` | `address`, `street`, `postcode`, `city`, `region` or `country`. |
| `radius:` | Search radius in metres, 1 to 5000. |
| `lang:` | Language of the result. |
| `boundaries:` | Add the administrative boundaries the point falls in (Australia). |
| `timezone:`, `elevation:`, `wikidata:`, `country_info:`, `codes:`, `sun:`, `regions:`, `districts:`, `census:`, `demographics:`, `road:`, `site:` | Each adds its extra block, as for `forward`. |
| `annotations:` | Adds every extra block at once. |

### autocomplete

Suggestions while someone types an address. Returns an `AutocompleteResponse` with a `suggestions` list; each
`Suggestion` has `text`, `lat`, `lon`, `type`, `precision` and `place_id`.

```ruby
typed = client.autocomplete("1600 Pennsylvania")
puts typed.suggestions[0].text # 1600 Pennsylvania Avenue NW, Washington, DC 20500, United States

client.autocomplete("1600 Pennsylvania", limit: 5, countries: "us")
```

Options: `limit:`, `countries:`, `proximity:`, `bounds:`, `strict:`, `types:` and `lang:`, as for `forward`.

### ip, ipv4, ipv6

Country, region, city, coordinates, timezone, network owner (ASN) and proxy, VPN and data centre flags for an IP
address. `ip` takes either version; `ipv4` and `ipv6` accept only their own. Without an address, they look up the
address the request comes from. Returns an `IpInfo`.

```ruby
google = client.ip("8.8.8.8")
puts "#{google.country} #{google.city}" # United States Mountain View
puts "#{google.asn} #{google.as_name}"  # 15169 Google LLC
puts google.is_datacenter               # true

client.ipv6("2001:4860:4860::8888")
client.ip                                # the address the request came from
client.ipv4("8.8.8.8", elevation: true) # adds elevation_m
```

Option: `elevation:`. The full list of `IpInfo` fields is under [Results and meta](#results-and-meta).

### timezone

The IANA zone, UTC offset, daylight saving state and local time for a point, now or at a given moment. Returns a
`TimezoneInfo`.

```ruby
tokyo = client.timezone(35.6762, 139.6503)
puts "#{tokyo.timezone} #{tokyo.utc_offset}"  # Asia/Tokyo +09:00
puts "#{tokyo.name} #{tokyo.abbreviation}"    # Japan Standard Time JST
puts tokyo.local_time                         # 2026-11-24T18:07:15+09:00

client.timezone(35.6762, 139.6503, timestamp: 1767225600)
client.timezone(tz: "Europe/Paris")
```

| Option | What it does |
|---|---|
| `tz:` | Look up a zone by its IANA or Windows id instead of a point (leave out `lat` and `lon`). |
| `timestamp:` | Unix time (or a `Time`) to answer for. Default: now. |
| `lang:` | Language of the zone name. Sent as the API's `language` parameter, only when you set it here or on the client. `language:` works as another name for this option. |
| `locations:` | Several points: `[[lat, lon], ...]`, or `"lat,lon\|lat,lon"` or an `enc:` polyline. |
| `path:`, `samples:` | Points along a path, sampled `samples` times (2 to 100). |
| `bounds:`, `rows:`, `cols:` | A grid of points over a box. |

For a plain list of points, `timezone_batch` is simpler.

### elevation

Height in metres above sea level (negative for the sea floor), from a global 15 arc-second grid. Returns an
`ElevationResponse` whose `results` holds `ElevationPoint` objects with `lat`, `lon`, `elevation_m` and
`resolution_m`.

```ruby
everest = client.elevation(27.9881, 86.9250)
puts everest.results[0].elevation_m # 8627.0

client.elevation(path: [[27.9881, 86.9250], [28.0, 86.85]], samples: 10)
```

Options: `locations:`, `path:` and `samples:`, or `bounds:`, `rows:` and `cols:`, as for `timezone` (leave out `lat`
and `lon`).

### postcode

A postal code to its place, region and coordinates. Returns a `PostcodeResponse` whose `results` lists every place
that uses the code.

```ruby
first = client.postcode("10001", country: "US").results[0]
puts "#{first.place} #{first.region_code}" # New York NY
puts "#{first.lat} #{first.lon}"           # 40.748401 -73.996702

client.postcode("75008", country: "FR")
```

Option: `country:` (ISO alpha-2). Without it, the code is matched in every country.

### forward_batch

Up to 100 searches in one request (each counts as one request against your quota). Returns a
`ForwardBatchResponse` whose `results` holds one `ForwardBatchEntry` per search, in the order you sent them; each
entry has the `query` and its own `results` list of `Place` objects.

```ruby
batch = client.forward_batch(["Brandenburg Gate, Berlin", "Sydney Opera House", "Statue of Liberty, New York"])
batch.results.each { |entry| puts "#{entry.query}: #{entry.results[0].formatted}" }
# Brandenburg Gate, Berlin: Brandenburg Gate, State of Berlin, Germany
# Sydney Opera House: Sydney Opera House, Sydney, New South Wales, Australia
# Statue of Liberty, New York: Statue of Liberty, New York, New York, United States

client.forward_batch(["Brandenburg Gate, Berlin", "Sydney Opera House"], limit: 1, timezone: true)
```

The options apply to every search in the batch: `limit:`, `countries:`, `bounds:`, `strict:`, `proximity:`,
`types:`, `lang:` and the extra blocks, as for `forward`. Structured fields and `place_id` are not available in a
batch; use `forward` for those.

### reverse_batch

Up to 100 points in one request (each counts as one request). Returns a `ReverseBatchResponse` whose `results` holds
one `ReverseResponse` per point, in the order you sent them; its `result` is a `Place`, or `nil` when nothing is in
range.

```ruby
batch = client.reverse_batch([[48.8584, 2.2945], [40.6892, -74.0445], [-33.8568, 151.2153]])
batch.results.each { |point| puts point.result ? point.result.formatted : "nothing in range" }
# 5 Avenue Anatole France, 75007 Paris, France
# 1 Liberty Island, New York, NY 10004, United States
# 2B Macquarie Street, Sydney NSW 2000, Australia
```

It takes the same options as `reverse`, applied to every point in the batch.

### ip_batch, ipv4_batch, ipv6_batch

Up to 100 addresses in one request. `ip_batch` takes both versions mixed; `ipv4_batch` and `ipv6_batch` accept only
their own. Returns an `IpBatchResponse` whose `results` holds one `IpInfo` per address, in the order you sent them.
An address the API cannot read gets an entry whose `status` is `error` and whose `error` Hash explains why, while the
rest still answer.

```ruby
batch = client.ipv4_batch(["8.8.8.8", "1.1.1.1", "9.9.9.9"])
batch.results.each { |info| puts "#{info.ip}: #{info.as_name}" }
# 8.8.8.8: Google LLC
# 1.1.1.1: Cloudflare, Inc.
# 9.9.9.9: Quad9

client.ipv6_batch(["2001:4860:4860::8888", "2606:4700:4700::1111"])
client.ip_batch(["8.8.8.8", "2606:4700:4700::1111"], elevation: true)
```

Option: `elevation:`, adds `elevation_m` to every address.

### timezone_batch

Timezones for up to 100 points (or an `enc:` polyline String). Returns a `TimezoneBatchResponse` whose `results` holds
one `TimezoneInfo` per point, in the order you sent them.

```ruby
batch = client.timezone_batch([[48.8584, 2.2945], [40.6892, -74.0445], [-33.8568, 151.2153]])
batch.results.each { |zone| puts zone.timezone }
# Europe/Paris
# America/New_York
# Australia/Sydney
```

Options: `timestamp:` (Unix time or a `Time`, default now) and `lang:` (also accepted as `language:`), as for
`timezone`.

### elevation_batch

Heights for up to 100 points, sent as a POST body. Returns an `ElevationResponse`.

```ruby
batch = client.elevation_batch([[48.8584, 2.2945], [40.6892, -74.0445], [-33.8568, 151.2153]])
batch.results.each { |point| puts point.elevation_m }
# 37.0
# 0.0
# 10.0
```

## Results and meta

Results are plain objects whose readers carry the API's own field names, so the
[API documentation](https://www.mygeocode.com/docs/) describes them field by field:

```ruby
place = client.forward("Brandenburg Gate, Berlin").results[0]

puts place.formatted              # Brandenburg Gate, State of Berlin, Germany
puts place.precision              # house
puts place.components.poi         # Brandenburg Gate
puts place.components.country_code # de
p place.components.city           # nil (not every address has every part)
```

A field the API did not send is `nil`, so check for `nil` before you use one. The fields this SDK reads are never
renamed or removed from the API: if one ever has to go, it keeps coming back as `nil`, and your code keeps working. A
list that comes back as `null` reads as an empty Array, and the address parts in `components` are always Strings.
Every result object also has `raw` (and `to_h`), the decoded JSON as a Hash, so fields added to the API later are
readable before the SDK knows them: `place.raw["new_field"]`.

What each method returns, and the readers it has:

| Class | Returned by | Readers |
|---|---|---|
| `ForwardResponse` | `forward` | `status`, `query`, `results` (Array of `Place`), `meta`, `raw` |
| `ReverseResponse` | `reverse`, each entry of `reverse_batch` | `status`, `lat`, `lon`, `result` (`Place` or `nil`), `boundaries`, `meta`, `raw` |
| `Place` | inside forward and reverse results | `formatted`, `lat`, `lon`, `type`, `precision`, `confidence`, `place_id`, `components`, `bounds`, `distance_m`, `formatted_place`, `place`, `parcel`, `codes`, `population`, `un_locode`, `timezone`, `elevation_m`, `wikidata`, `country_info`, `sun`, `regions`, `districts`, `census`, `demographics`, `road`, `intersection`, `site`, `raw` |
| `Components` | `Place#components` | `poi`, `building`, `unit`, `level`, `house_number`, `road`, `lot`, `suburb`, `municipality`, `city`, `county`, `state`, `state_code`, `postcode`, `country`, `country_code`, `official_name`, `raw` |
| `Bounds` | `Place#bounds` | `north`, `south`, `east`, `west`, `raw` |
| `AutocompleteResponse` | `autocomplete` | `status`, `query`, `suggestions` (Array of `Suggestion`), `meta`, `raw` |
| `Suggestion` | inside autocomplete results | `text`, `lat`, `lon`, `type`, `precision`, `place_id`, `raw` |
| `IpInfo` | `ip`, `ipv4`, `ipv6`, each entry of the IP batches | `status`, `ip`, `version`, `found`, `prefix`, `country`, `country_code`, `continent`, `continent_code`, `region`, `region_code`, `city`, `postcode`, `lat`, `lon`, `elevation_m`, `timezone`, `utc_offset`, `utc_offset_seconds`, `is_eu`, `asn`, `as_name`, `org`, `usage_type`, `registry`, `allocated`, `tags`, `is_anycast`, `is_satellite`, `is_datacenter`, `is_proxy`, `is_vpn_provider`, `is_tor`, `crawler`, `is_private`, `reason`, `abuse_email`, `threat`, `updated_at`, `error`, `meta`, `raw` |
| `TimezoneInfo` | `timezone`, each entry of `timezone_batch` | `status`, `lat`, `lon`, `timezone`, `name`, `abbreviation`, `utc_offset`, `utc_offset_seconds`, `raw_offset_seconds`, `dst`, `dst_offset_seconds`, `timestamp`, `local_time`, `country_code`, `is_ocean`, `windows_timezone`, `next_transition` (`TimezoneTransition`), `meta`, `raw` |
| `TimezoneTransition` | `TimezoneInfo#next_transition` | `timestamp`, `utc_offset`, `utc_offset_seconds`, `dst`, `abbreviation`, `raw` |
| `ElevationResponse` | `elevation`, `elevation_batch` | `status`, `results` (Array of `ElevationPoint`), `meta`, `raw` |
| `ElevationPoint` | inside elevation results | `lat`, `lon`, `elevation_m`, `resolution_m`, `raw` |
| `PostcodeResponse` | `postcode` | `status`, `postcode`, `country_code`, `results` (Array of `PostcodePlace`), `meta`, `raw` |
| `PostcodePlace` | inside postcode results | `postcode`, `place`, `region`, `region_code`, `country`, `country_code`, `lat`, `lon`, `raw` |
| `ForwardBatchResponse` | `forward_batch` | `status`, `results` (Array of `ForwardBatchEntry`), `meta`, `raw` |
| `ForwardBatchEntry` | inside forward batch results | `query`, `results` (Array of `Place`), `raw` |
| `ReverseBatchResponse` | `reverse_batch` | `status`, `results` (Array of `ReverseResponse`), `meta`, `raw` |
| `IpBatchResponse` | `ip_batch`, `ipv4_batch`, `ipv6_batch` | `status`, `results` (Array of `IpInfo`), `meta`, `raw` |
| `TimezoneBatchResponse` | `timezone_batch` | `status`, `timestamp`, `results` (Array of `TimezoneInfo`), `meta`, `raw` |

The extra blocks you ask for with the flags (`timezone`, `elevation`, `wikidata` and the rest) are readers of `Place`
and stay plain Hashes. On an entry inside a batch, `meta` is `nil`; the batch response has the meta.

Every response object has `meta`, filled from the response headers (`nil` when a header was not sent):

| Reader | Header | Meaning |
|---|---|---|
| `request_id` | `X-Request-Id` | Quote it when you contact support. |
| `quota_limit` | `X-Quota-Limit` | Free requests a day for this key's account or network. |
| `quota_used` | `X-Quota-Used` | Free requests used today. |
| `quota_free_remaining` | `X-Quota-Free-Remaining` | Free requests left today. |
| `quota_reset` | `X-Quota-Reset` | Unix time when the free requests reset. |
| `credits_remaining` | `X-Credits-Remaining` | Prepaid credit left, when a key with credit is used. |

## Errors

Everything the SDK raises derives from `MyGeocode::MyGeocodeError`:

| Class | When |
|---|---|
| `MyGeocode::ApiError` | The API answered with an error. `status` is the HTTP status, `code` the API's error code (such as `invalid_request`, `invalid_key` or `quota_exceeded`), `message` its explanation, `param` the parameter at fault, `request_id`, `retry_after` (seconds, or `nil`) and `body` (the decoded answer). |
| `MyGeocode::RequestTimeoutError` | No answer within `timeout`. |
| `MyGeocode::NetworkError` | The connection failed: DNS, refused, reset or TLS. |
| `MyGeocode::DecodeError` | The answer could not be read as JSON. |

```ruby
begin
  found = client.forward("Brandenburg Gate, Berlin")
  puts "#{found.results.size} results" # 5 results
rescue MyGeocode::ApiError => e
  puts "#{e.status} #{e.code} #{e.message}"
rescue MyGeocode::MyGeocodeError => e
  puts "Could not reach the API: #{e.message}"
end
```

The [errors page](https://www.mygeocode.com/docs/errors/) lists every error code.

## Retries

The client retries on its own, up to `max_retries` times (default 2):

- **429** (too many requests): waits for `Retry-After`, or until `X-Quota-Reset`. If that is longer than
  `max_retry_wait` (default 60 seconds), for example when the day's free requests are gone, it raises the `ApiError`
  straight away instead of waiting.
- **500**: tries once more after one second.
- **503**: waits for `Retry-After`, or 1, 2 and then 4 seconds.
- **Timeouts and connection errors**: retried with the same 1, 2, 4 second pattern for GET requests. The POST batch
  calls are not retried after a connection error, so a batch is never charged twice.

Other errors are raised at once.

## Configuration

All options are optional:

```ruby
client = MyGeocode::Client.new(
  key: "YOUR_KEY",                         # default: MYGEOCODE_KEY, else no key
  base_url: "https://api.mygeocode.com/v1",
  timeout: 10,                             # seconds, for connecting and for each read and write
  max_retries: 2,
  max_retry_wait: 60,                      # seconds
  lang: "en"
)
```

`transport:`, `sleep:` and `clock:` replace the HTTP layer, the wait and the clock (seconds since the epoch) the retry
logic uses. They are meant for tests, see below.

The default transport is `Net::HTTP`: one connection per request, the system's certificate store, and the
`http_proxy` / `https_proxy` environment variables as `Net::HTTP` reads them.

## Testing your code (transport hook)

The client sends every request through its `transport`: anything with a `call` method that takes a
`MyGeocode::HttpRequest` (`method`, `url`, `headers`, `body`, `timeout`) and returns a `MyGeocode::HttpResponse`
(`status`, `headers`, `body`). A lambda works. Give it your own to test code that uses the SDK without touching the
network:

```ruby
require "json"

canned = lambda do |_request|
  body = {
    "status" => "ok", "lat" => 48.8584, "lon" => 2.2945,
    "result" => { "formatted" => "5 Avenue Anatole France, 75007 Paris, France", "lat" => 48.858821, "lon" => 2.294596 }
  }
  MyGeocode::HttpResponse.new(200, { "Content-Type" => "application/json" }, JSON.generate(body))
end

client = MyGeocode::Client.new(transport: canned, sleep: ->(_seconds) {}) # no real waiting in retry tests
puts client.reverse(48.8584, 2.2945).result.formatted # 5 Avenue Anatole France, 75007 Paris, France
```

The same hook plugs in any HTTP library, such as Faraday or HTTP.rb with your own connection pool and proxy settings.
Raise `MyGeocode::RequestTimeoutError` for a timeout and `MyGeocode::NetworkError` for any other failure to get an
answer; return every HTTP status as an `HttpResponse`.

### Running the SDK's own tests

The tests need nothing but Ruby, so the same suite runs on every version from 2.4 up. They answer from real recorded
API responses (and a small local server for the transport) and never call the API:

```bash
ruby -w test/run.rb      # or: rake test
```

Any warning counts as a failed test.

## Requirements

- Ruby 2.4 or newer. Tested on 2.4, 2.5, 2.6, 2.7, 3.0, 3.1, 3.2, 3.3, 3.4, 4.0 and 4.1 (preview), with every warning
  treated as a failure (`-w`, and `-W:deprecated` from 2.7).
- Nothing else: only the standard library (`net/http`, `openssl`, `json`, `uri`).

## Links

- [API documentation](https://www.mygeocode.com/docs/)
- [Pricing and free tier](https://www.mygeocode.com/pricing/)
- [Dashboard and API keys](https://www.mygeocode.com/dashboard)
- [Issues](https://github.com/mygeocode/mygeocode-ruby/issues)
- Support: [support@mygeocode.com](mailto:support@mygeocode.com)

## Licence

MIT. See [LICENSE](LICENSE).
