# frozen_string_literal: true

# A small test runner with no dependencies, so the same suite runs on every Ruby from 2.4: every test_ method of
# every Tests::Case subclass in test/*_test.rb runs in a fresh instance. Any warning Ruby prints fails the run.
#
#   ruby -w test/run.rb            (on Ruby 2.7 and newer also -W:deprecated)

$warnings = []
module Warning
  def self.warn(message, *)
    $warnings << message
    $stderr.write("WARNING: #{message}")
  end
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(__dir__)
require "helper"
Dir[File.join(__dir__, "*_test.rb")].sort.each { |file| require File.basename(file, ".rb") }

passed = 0
failures = []
Tests::Case.cases.each do |klass|
  klass.instance_methods(false).grep(/\Atest_/).sort.each do |name|
    test = klass.new
    begin
      test.setup
      test.send(name)
      passed += 1
    rescue Exception => e # rubocop:disable Lint/RescueException
      failures << "#{klass.name}##{name}: #{e.class}: #{e.message}\n    #{(e.backtrace || []).first(4).join("\n    ")}"
    ensure
      test.teardown
    end
  end
end
failures.each { |f| puts "FAIL #{f}" }
puts "#{passed} passed, #{failures.size} failed, #{$warnings.size} warnings (Ruby #{RUBY_VERSION})"
exit(failures.empty? && $warnings.empty? ? 0 : 1)
