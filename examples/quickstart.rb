# frozen_string_literal: true

# One forward and one reverse call, without a key: the network's free requests apply.
#   ruby -Ilib examples/quickstart.rb
require "mygeocode"

client = MyGeocode::Client.new

found = client.forward("Brandenburg Gate, Berlin", limit: 1)
found.results.each { |place| puts "#{place.formatted} (#{place.lat}, #{place.lon})" }

address = client.reverse(48.8584, 2.2945)
puts address.result ? address.result.formatted : "nothing nearby"
puts "free requests left today: #{address.meta.quota_free_remaining}" if address.meta.quota_free_remaining
