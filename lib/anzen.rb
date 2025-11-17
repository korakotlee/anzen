# frozen_string_literal: true

require_relative 'anzen/version'
require_relative 'anzen/exceptions'
require_relative 'anzen/monitor'
require_relative 'anzen/monitors/call_stack_depth'
require_relative 'anzen/monitors/recursion'
require_relative 'anzen/monitors/memory'
require_relative 'anzen/registry'
require_relative 'anzen/configuration'

# Anzen - Runtime safety protection gem
#
# Provides safety monitoring for recursion, memory, and other runtime concerns.
# Use Anzen.setup to initialize with monitors and configuration.
#
# @example Basic usage
#   Anzen.setup(config: { enabled_monitors: ['recursion'], monitors: { recursion: { depth_limit: 1000 } } })
#   # ... your code ...
#   Anzen.check!  # Raises if any monitor detects violation
#
# @api public
module Anzen
  # @!visibility private
  @@registry = nil

  # @!visibility private
  @@initialized = false

  # Setup Anzen with configuration and monitors
  #
  # Initializes the registry, creates and registers default monitors, and enables specified ones.
  # Can only be called once per process.
  #
  # @param config [Hash] configuration hash with keys:
  #   - enabled_monitors (Array): list of monitor names to enable
  #   - monitors (Hash): per-monitor configurations
  # @raise [InitializationError] if Anzen is already initialized
  # @raise [ConfigurationError] if configuration is invalid
  # @return [void]
  #
  # @example
  #   Anzen.setup(config: {
  #     enabled_monitors: ['recursion'],
  #     monitors: { recursion: { depth_limit: 500 } }
  #   })
  def self.setup(config: {})
    raise Anzen::InitializationError if @@initialized

    @@registry = Registry.new
    configuration = Configuration.programmatic(config)

    # Register CallStackDepthMonitor
    depth_limit = 1000
    begin
      depth_limit = configuration.monitor_config('call_stack_depth')['depth_limit']
    rescue Anzen::ConfigurationError
      # Use default if not configured
    end

    call_stack_depth_monitor = Monitors::CallStackDepthMonitor.new(depth_limit: depth_limit)
    @@registry.register(call_stack_depth_monitor)

    # Register RecursionMonitor
    recursion_config = {}
    begin
      recursion_config = configuration.monitor_config('recursion')
    rescue Anzen::ConfigurationError
      # Use defaults if not configured
    end
    depth_limit = recursion_config['depth_limit'] || 1000

    recursion_monitor = Monitors::RecursionMonitor.new(depth_limit: depth_limit)
    @@registry.register(recursion_monitor)

    # Register MemoryMonitor
    memory_config = {}
    begin
      memory_config = configuration.monitor_config('memory')
    rescue Anzen::ConfigurationError
      # Use defaults if not configured
    end
    limit_mb = memory_config['limit_mb'] || 512
    sampling_interval_ms = memory_config['sampling_interval_ms'] || 100

    memory_monitor = Monitors::MemoryMonitor.new(
      limit_mb: limit_mb,
      sampling_interval_ms: sampling_interval_ms
    )
    @@registry.register(memory_monitor)

    # Enable specified monitors
    @@registry.enable('call_stack_depth') if configuration.monitor_enabled?('call_stack_depth')
    @@registry.enable('recursion') if configuration.monitor_enabled?('recursion')
    @@registry.enable('memory') if configuration.monitor_enabled?('memory')

    @@initialized = true
  end

  # Enable a monitor by name
  #
  # @param name [String] monitor name
  # @raise [MonitorNotFoundError] if monitor not found
  # @return [void]
  def self.enable(name)
    ensure_initialized
    @@registry.enable(name)
  end

  # Disable a monitor by name
  #
  # @param name [String] monitor name
  # @raise [MonitorNotFoundError] if monitor not found
  # @return [void]
  def self.disable(name)
    ensure_initialized
    @@registry.disable(name)
  end

  # Execute all enabled monitors' checks
  #
  # Runs check! on each enabled monitor. Raises immediately if any violation detected.
  #
  # @raise [ViolationError] subclass on first violation detected
  # @raise [CheckFailedError] on infrastructure failure
  # @return [nil]
  def self.check!
    ensure_initialized
    @@registry.check_all!
  end

  # Return status of all monitors
  #
  # @return [Hash] status hash with keys:
  #   - monitors (Array): array of monitor status hashes
  #   - enabled_count (Integer): number of enabled monitors
  #   - violations_total (Integer): total violations across all monitors
  def self.status
    ensure_initialized
    @@registry.status
  end

  # Register a custom monitor
  #
  # Monitor must implement the Monitor interface.
  #
  # @param monitor [Anzen::Monitor] monitor instance
  # @raise [InvalidMonitorError] if monitor doesn't implement required interface
  # @raise [MonitorNameConflictError] if monitor name already registered
  # @return [void]
  def self.register_monitor(monitor)
    ensure_initialized
    @@registry.register(monitor)
  end

  class << self
    private

    # Ensure Anzen is initialized
    #
    # @raise [InitializationError] if not initialized
    def ensure_initialized
      raise Anzen::InitializationError, 'Anzen not initialized. Call Anzen.setup first.' unless @@initialized
    end
  end
end
