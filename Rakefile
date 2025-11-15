# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: %i[spec rubocop]

namespace :ci do
  desc "Run all CI checks (tests + lint)"
  task check: %i[spec rubocop]
end

namespace :coverage do
  desc "Show test coverage report"
  task report: :spec do
    require "simplecov"
    puts "\nCoverage report available in coverage/index.html"
  end
end
