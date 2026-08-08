require "bundler/setup"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :matrix

desc "Run the test suite against every Appraisal (Rails 7.1 / 7.2 / 8.0)"
task :matrix do
  sh "bundle exec appraisal install"
  sh "bundle exec appraisal rspec"
end