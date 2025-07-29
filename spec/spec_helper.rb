# frozen_string_literal: true

require 'rack/test'
require 'rspec'
require 'webmock/rspec'
require_relative '../lib/webmention_forwarder'

# Configure WebMock to prevent real HTTP requests during testing
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.include Rack::Test::Methods
  
  # Use documentation formatter for better output
  config.default_formatter = 'doc' if config.files_to_run.one?
  
  # Run specs in random order to surface order dependencies
  config.order = :random
  
  # Seed global randomization in this process using the `--seed` CLI option
  Kernel.srand config.seed
  
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  
  config.shared_context_metadata_behavior = :apply_to_host_groups
end