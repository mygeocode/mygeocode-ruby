# frozen_string_literal: true

# Smoke test against the live API: 8 calls, one per endpoint family. Run it by hand, never from the unit tests:
#   ruby -Ilib examples/smoke.rb
require "mygeocode"

client = MyGeocode::Client.new
failed = false
check = lambda do |name, &call|
  begin
    puts format("ok   %-15s %s", name, call.call)
  rescue MyGeocode::MyGeocodeError, NoMethodError => e
    failed = true
    puts format("FAIL %-15s %s: %s", name, e.class, e.message)
  end
end

check.call("forward") { client.forward("Brandenburg Gate, Berlin", limit: 1).results[0].formatted }
check.call("reverse") { client.reverse(48.8584, 2.2945).result.formatted }
check.call("autocomplete") { client.autocomplete("1600 Pennsylvania", limit: 2).suggestions[0].text }
check.call("ipv4") { client.ipv4("8.8.8.8").as_name }
check.call("timezone") { client.timezone(35.6762, 139.6503).timezone }
check.call("elevation") { client.elevation(27.9881, 86.9250).results[0].elevation_m }
check.call("postcode") { client.postcode("10001", country: "US").results[0].place }
check.call("elevation batch") { "#{client.elevation_batch([[48.8584, 2.2945], [-33.8568, 151.2153]]).results.size} points" }

exit(failed ? 1 : 0)
