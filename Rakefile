# frozen_string_literal: true

desc "Run the tests (every warning fails the run)"
task :test do
  flags = ["-w"]
  flags << "-W:deprecated" if RUBY_VERSION >= "2.7"
  ruby(*flags, "test/run.rb")
end

task default: :test
