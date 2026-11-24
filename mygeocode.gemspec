# frozen_string_literal: true

require_relative "lib/mygeocode/version"

Gem::Specification.new do |spec|
  spec.name = "mygeocode"
  spec.version = MyGeocode::VERSION
  spec.authors = ["My Geocode"]
  spec.email = ["support@mygeocode.com"]

  spec.summary = "Official Ruby client for the My Geocode API: geocoding, reverse geocoding, autocomplete, IP, " \
                 "timezone, elevation and postal code lookups."
  spec.description = "Forward and reverse geocoding, address autocomplete, IPv4 and IPv6 lookup, timezones, " \
                     "elevation and postal codes from the My Geocode API. Standard library only (Net::HTTP and " \
                     "json), Ruby 2.4 and newer; the API key is optional."
  spec.homepage = "https://www.mygeocode.com/sdks/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.4"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => "https://www.mygeocode.com/docs/",
    "source_code_uri" => "https://github.com/mygeocode/mygeocode-ruby",
    "bug_tracker_uri" => "https://github.com/mygeocode/mygeocode-ruby/issues"
  }

  spec.files = Dir["lib/**/*.rb"] + ["LICENSE", "README.md"]
  spec.require_paths = ["lib"]
end
