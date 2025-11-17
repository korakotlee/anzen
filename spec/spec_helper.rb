# frozen_string_literal: true

# SimpleCov must be loaded BEFORE anything else
require 'simplecov'

SimpleCov.start do
  enable_coverage :branch

  add_filter '/spec/'
  add_filter '/bin/'
  add_filter '/vendor/'

  add_group 'Core', 'lib/anzen/core'
  add_group 'Monitors', 'lib/anzen/monitors'
  add_group 'Configuration', 'lib/anzen/config'
  add_group 'CLI', 'lib/anzen/cli'
  add_group 'Exceptions', 'lib/anzen/exceptions'

  minimum_coverage 80
  minimum_coverage_by_file 75
end

# Load RSpec
require 'rspec'

# RSpec configuration
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/.rspec_status'
  config.disable_monkey_patching!
  config.warnings = true
  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Reset Anzen before each test to ensure clean state
  config.before(:each) do
    Anzen._reset_for_testing
  end
end

# Load the gem
require 'anzen'
