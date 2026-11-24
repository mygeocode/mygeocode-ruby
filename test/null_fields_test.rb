# frozen_string_literal: true

module Tests
  # The API may one day answer a field with null instead of dropping it (fields this library reads are never
  # removed; they become null). Every method must keep working: a null field stays nil (never a made-up 0 or ""), a
  # null list reads as an empty list and a null object as nil, with no error or warning.
  #
  # Each recorded answer is replayed twice: once with every scalar set to null ("leaves"), once with every value set
  # to null, lists and objects included ("all"). Only the top-level "status" stays "ok".
  class NullFieldsTest < Case
    CALLS = [
      ["forward", ->(c) { c.forward("Brandenburg Gate, Berlin") }],
      ["reverse", ->(c) { c.reverse(*EIFFEL) }],
      ["autocomplete", ->(c) { c.autocomplete("1600 Pennsylvania") }],
      ["ip", ->(c) { c.ip("8.8.8.8") }],
      ["ipv4", ->(c) { c.ipv4("8.8.8.8") }],
      ["ipv6", ->(c) { c.ipv6("2001:4860:4860::8888") }],
      ["timezone", ->(c) { c.timezone(35.6762, 139.6503) }],
      ["elevation", ->(c) { c.elevation(27.9881, 86.9250) }],
      ["postcode", ->(c) { c.postcode("10001", country: "US") }],
      ["forward_batch", ->(c) { c.forward_batch(["Brandenburg Gate, Berlin", "Sydney Opera House"]) }],
      ["reverse_batch", ->(c) { c.reverse_batch([EIFFEL, LIBERTY]) }],
      ["ip_batch", ->(c) { c.ip_batch(["8.8.8.8", "2606:4700:4700::1111"]) }],
      ["ipv4_batch", ->(c) { c.ipv4_batch(["8.8.8.8", "1.1.1.1", "9.9.9.9"]) }],
      ["ipv6_batch", ->(c) { c.ipv6_batch(["2001:4860:4860::8888"]) }],
      ["timezone_batch", ->(c) { c.timezone_batch([EIFFEL, LIBERTY]) }],
      ["elevation_batch", ->(c) { c.elevation_batch([EIFFEL, LIBERTY]) }]
    ].freeze

    def nullify(value, everything, top = true)
      return nil unless value.is_a?(Hash)

      out = {}
      value.each do |key, item|
        out[key] = if top && key == "status"
                     "ok"
                   elsif everything || !(item.is_a?(Hash) || item.is_a?(Array))
                     nil
                   elsif item.is_a?(Array)
                     item.map { |i| i.is_a?(Hash) ? nullify(i, false, false) : nil }
                   else
                     nullify(item, false, false)
                   end
      end
      out
    end

    # Every field of the result tree (meta and raw aside) must be nil, an empty list, or hold only nils.
    def non_null(value, path, found)
      case value
      when MyGeocode::Model
        value.class.fields.each do |name|
          item = value.public_send(name)
          non_null(item, "#{path}.#{name}", found) unless name == "status" && item == "ok"
        end
      when Array
        value.each_with_index { |item, i| non_null(item, "#{path}[#{i}]", found) }
      when Hash
        value.each { |key, item| non_null(item, "#{path}[#{key.inspect}]", found) }
      when nil
        nil
      else
        found << "#{path} = #{value.inspect}"
      end
    end

    def check(everything)
      CALLS.each do |name, call|
        body = nullify(Tests.recording(name)["body"], everything)
        result = call.call(client(Recorder.new(Tests.answer(200, body))))
        found = []
        non_null(result, name, found)
        assert_equal([], found, "#{everything ? 'all' : 'leaves'} null: fields must stay nil")
        assert_equal("ok", result.status, name)
      end
    end

    def test_every_scalar_null_stays_nil
      check(false)
    end

    def test_every_value_null_including_lists_and_objects
      check(true)
    end

    def test_null_lists_read_as_empty_lists
      r = client(Recorder.new(Tests.answer(200, "status" => "ok", "query" => nil, "results" => nil))).forward("x")
      assert_equal([], r.results)
      r = client(Recorder.new(Tests.answer(200, "status" => "ok", "lat" => nil, "lon" => nil, "result" => nil))).reverse(*EIFFEL)
      assert_nil(r.result)
      assert_nil(r.lat)
      r = client(Recorder.new(Tests.answer(200, "status" => "ok", "ip" => "8.8.8.8", "tags" => nil))).ip("8.8.8.8")
      assert_equal([], r.tags)
    end
  end
end
