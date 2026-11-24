# frozen_string_literal: true

module MyGeocode
  # Base of every result: builds itself from a decoded JSON object.
  #
  # Every field can be nil: the API never drops a field this library reads, it sends null instead, and a field it
  # did not send at all reads as nil too. A list that arrives as null (or is missing) reads as an empty list.
  # #raw always holds the decoded JSON object, so fields this version does not know yet are still there.
  class Model
    class << self
      # The API fields of the class, in order.
      def fields
        @fields ||= []
      end

      # Fields holding one object of a Model class: name => class.
      def objects
        @objects ||= {}
      end

      # Fields holding a list: name => class of the entries, or nil for plain values.
      def lists
        @lists ||= {}
      end

      # Fields whose value is always text.
      def text
        @text ||= []
      end

      # Whether the class has meta (the answer of a method, rather than a part of one).
      def meta?
        false
      end

      # Builds the object from a decoded JSON object (anything else reads as an empty one).
      def from_hash(data, meta = nil)
        data = {} unless data.is_a?(Hash)
        obj = allocate
        obj.send(:fill, data, meta)
        obj
      end

      private

      def field(*names, object: nil, list: false, entry: nil, text: false)
        names.each do |name|
          name = name.to_s
          fields << name
          objects[name] = object if object
          lists[name] = entry if list
          self.text << name if text
          attr_reader name
        end
      end
    end

    # The decoded JSON object, exactly as the API sent it.
    attr_reader :raw

    # The same as #raw.
    def to_h
      raw
    end

    def ==(other)
      other.class == self.class && other.raw == raw
    end
    alias eql? ==

    def hash
      [self.class, raw].hash
    end

    def inspect
      shown = self.class.fields.first(4).map { |name| "#{name}=#{instance_variable_get("@#{name}").inspect}" }
      "#<#{self.class.name} #{shown.join(', ')}>"
    end

    private

    def fill(data, meta)
      klass = self.class
      klass.fields.each do |name|
        value = data[name]
        if klass.lists.key?(name)
          entry = klass.lists[name]
          value = if !value.is_a?(Array)
                    []
                  elsif entry
                    value.map { |item| item.is_a?(Hash) ? MyGeocode.const_get(entry).from_hash(item) : nil }
                  else
                    value
                  end
        elsif klass.objects.key?(name)
          value = value.is_a?(Hash) ? MyGeocode.const_get(klass.objects[name]).from_hash(value) : nil
        elsif klass.text.include?(name) && !value.nil? && !value.is_a?(String)
          value = value.is_a?(Numeric) ? value.to_s : nil
        end
        instance_variable_set("@#{name}", value)
      end
      @raw = data
      @meta = meta if klass.meta?
    end
  end


  # The box around a place, in degrees.
  class Bounds < Model
    field :north, :south, :east, :west
  end

  # The parts of an address. Every part is text (a number the API sends here is turned into text), nil when the
  # address has no such part.
  class Components < Model
    field :poi, :building, :unit, :level, :house_number, :road, :lot, :suburb, :municipality, :city, :county, :state,
          :state_code, :postcode, :country, :country_code, :official_name, text: true
  end

  # One forward or reverse result. The extra blocks you ask for with the flags (timezone, codes, sun ...) are plain
  # hashes, nil when not asked for.
  class Place < Model
    field :formatted, :lat, :lon, :type, :precision, :confidence, :place_id
    field :components, object: :Components
    field :bounds, object: :Bounds
    field :distance_m, :formatted_place, :place, :parcel, :codes, :population, :un_locode, :timezone, :elevation_m,
          :wikidata, :country_info, :sun, :regions, :districts, :census, :demographics, :road, :intersection, :site
  end

  # The answer of forward: the matches, best first.
  class ForwardResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status, :query
    field :results, list: true, entry: :Place
  end

  # One search of a forward batch.
  class ForwardBatchEntry < Model
    field :query
    field :results, list: true, entry: :Place
  end

  # The answer of forward_batch.
  class ForwardBatchResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status
    field :results, list: true, entry: :ForwardBatchEntry
  end

  # The answer of reverse, and one entry of a reverse batch. result is nil when nothing is in range.
  class ReverseResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status, :lat, :lon
    field :result, object: :Place
    field :boundaries
  end

  # The answer of reverse_batch.
  class ReverseBatchResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status
    field :results, list: true, entry: :ReverseResponse
  end

  # One autocomplete suggestion.
  class Suggestion < Model
    field :text, :lat, :lon, :type, :precision, :place_id
  end

  # The answer of autocomplete.
  class AutocompleteResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status, :query
    field :suggestions, list: true, entry: :Suggestion
  end

  # An IPv4 or IPv6 lookup, and one entry of an IP batch. In a batch, an address the API cannot read has the status
  # "error" and an error hash.
  class IpInfo < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status, :ip, :version, :found, :prefix, :country, :country_code, :continent, :continent_code, :region,
          :region_code, :city, :postcode, :lat, :lon, :elevation_m, :timezone, :utc_offset, :utc_offset_seconds,
          :is_eu, :asn, :as_name, :org, :usage_type, :registry, :allocated
    field :tags, list: true
    field :is_anycast, :is_satellite, :is_datacenter, :is_proxy, :is_vpn_provider, :is_tor, :crawler, :is_private,
          :reason, :abuse_email, :threat, :updated_at, :error
  end

  # The answer of ip_batch, ipv4_batch and ipv6_batch.
  class IpBatchResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status
    field :results, list: true, entry: :IpInfo
  end

  # The next change of UTC offset, such as the start or end of daylight saving time.
  class TimezoneTransition < Model
    field :timestamp, :utc_offset, :utc_offset_seconds, :dst, :abbreviation
  end

  # The answer of timezone, and one entry of a timezone batch.
  class TimezoneInfo < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status, :lat, :lon, :timezone, :name, :abbreviation, :utc_offset, :utc_offset_seconds,
          :raw_offset_seconds, :dst, :dst_offset_seconds, :timestamp, :local_time, :country_code, :is_ocean,
          :windows_timezone
    field :next_transition, object: :TimezoneTransition
  end

  # The answer of timezone_batch.
  class TimezoneBatchResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status, :timestamp
    field :results, list: true, entry: :TimezoneInfo
  end

  # The height of one point: elevation_m in metres above sea level (negative for the sea floor), resolution_m the
  # size of the grid cell.
  class ElevationPoint < Model
    field :lat, :lon, :elevation_m, :resolution_m
  end

  # The answer of elevation and elevation_batch. It always has results, one entry for a single point.
  class ElevationResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status
    field :results, list: true, entry: :ElevationPoint
  end

  # One place that uses a postal code.
  class PostcodePlace < Model
    field :postcode, text: true
    field :place, :region, :region_code, :country, :country_code, :lat, :lon
  end

  # The answer of postcode.
  class PostcodeResponse < Model
    # The request id and quota figures from the response headers (nil on an entry inside a batch).
    attr_reader :meta

    def self.meta?
      true
    end

    field :status
    field :postcode, text: true
    field :country_code
    field :results, list: true, entry: :PostcodePlace
  end
end
