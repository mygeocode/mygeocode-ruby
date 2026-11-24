# frozen_string_literal: true

require "json"
require "uri"
require "mygeocode"

module Tests
  FIXTURES = File.join(__dir__, "fixtures")
  EIFFEL = [48.8584, 2.2945].freeze
  LIBERTY = [40.6892, -74.0445].freeze
  OPERA = [-33.8568, 151.2153].freeze

  class AssertionFailed < StandardError
  end

  # A recorded answer: {"request" => {...}, "status" => ..., "headers" => {...}, "body" => {...}}.
  def self.recording(name)
    JSON.parse(File.read(File.join(FIXTURES, "#{name}.json"), encoding: "UTF-8"))
  end

  def self.answer(status = 200, body = nil, headers = {}, text = nil)
    MyGeocode::HttpResponse.new(status, headers, text.nil? ? JSON.generate(body) : text)
  end

  # The recorded status, headers and body of a recording, optionally overridden.
  def self.replay(name, status: nil, headers: {})
    rec = recording(name)
    merged = rec["headers"].dup
    headers.each { |k, v| merged[k.downcase] = v }
    answer(status || rec["status"], rec["body"], merged)
  end

  # A request as the transport received it, with the URL taken apart.
  class Sent
    attr_reader :method, :url, :headers, :body, :timeout, :path, :query

    def initialize(request)
      @method = request.method
      @url = request.url
      @headers = MyGeocode::Headers.new(request.headers)
      @body = request.body
      @timeout = request.timeout
      uri = URI.parse(request.url)
      @path = uri.path
      @query = Hash[URI.decode_www_form(uri.query || "")]
    end

    def json
      @body.nil? ? nil : JSON.parse(@body)
    end
  end

  # Collects requests and answers with the queued responses in turn (the last one repeats). A queued exception is
  # raised instead of answering.
  class Recorder
    attr_reader :sent

    def initialize(*responses)
      @sent = []
      @queue = responses
    end

    def call(request)
      @sent << Sent.new(request)
      item = @queue.size > 1 ? @queue.shift : @queue.first
      raise item if item.is_a?(Exception)

      item
    end

    def last
      @sent.last
    end
  end

  # Base of every test class.
  class Case
    @cases = []

    class << self
      attr_reader :cases

      def inherited(klass)
        super
        Case.cases << klass
      end
    end

    attr_reader :sleeps

    def setup
      @saved_key = ENV.delete("MYGEOCODE_KEY")
      @sleeps = []
    end

    def teardown
      ENV.delete("MYGEOCODE_KEY")
      ENV["MYGEOCODE_KEY"] = @saved_key unless @saved_key.nil?
    end

    def client(transport, **options)
      sleeps = @sleeps
      options[:sleep] ||= ->(seconds) { sleeps << seconds }
      options[:clock] ||= -> { 1000.0 }
      MyGeocode::Client.new(transport: transport, **options)
    end

    def assert(value, message = "expected a true value")
      raise AssertionFailed, message unless value
    end

    def assert_equal(want, got, message = nil)
      return if want == got

      raise AssertionFailed, "#{message ? "#{message}: " : ''}want #{want.inspect}, got #{got.inspect}"
    end

    def assert_nil(value, message = nil)
      assert_equal(nil, value, message)
    end

    def assert_raises(klass)
      yield
    rescue klass => e
      e
    else
      raise AssertionFailed, "expected #{klass} to be raised"
    end

    def assert_instance_of(klass, value)
      raise AssertionFailed, "want a #{klass}, got #{value.inspect}" unless value.instance_of?(klass)
    end

    def refute_key(hash, key)
      raise AssertionFailed, "#{key.inspect} should not be in #{hash.inspect}" if hash.key?(key)
    end

    def same?(a, b)
      return true if a == b

      Float(a) == Float(b)
    rescue ArgumentError, TypeError
      false
    end

    # The request equals the recorded one: method, path, every query parameter and the JSON body.
    def assert_sent_like(name, sent)
      want = Tests.recording(name)["request"]
      assert_equal(want["method"], sent.method, "method of #{name}")
      assert_equal(want["path"], sent.path, "path of #{name}")
      assert_equal(want["query"].keys.sort, sent.query.keys.sort, "query of #{name}")
      want["query"].each do |key, value|
        assert(same?(sent.query[key], value.to_s), "#{name}: #{key}: #{sent.query[key].inspect} != #{value.inspect}")
      end
      assert_equal(want["body"], sent.json, "body of #{name}")
    end
  end
end
