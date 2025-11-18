# frozen_string_literal: true

require 'set'

module Anzen
  # Registry for managing safety monitors
  #
  # Handles registration, lifecycle management, and coordination of monitors.
  # Thread-safe for monitor state queries.
  #
  # @api public
  class Registry
    # Initialize Registry
    def initialize
      @monitors = {}
      @enabled_monitors = Set.new
      @violations_count = {}
      @mutex = Mutex.new
    end

    # Register a monitor
    #
    # @param monitor [Anzen::Monitor] monitor instance implementing Monitor interface
    # @raise [InvalidMonitorError] if monitor doesn't implement required interface
    # @raise [MonitorNameConflictError] if monitor name already registered
    def register(monitor)
      validate_monitor_interface(monitor)

      @mutex.synchronize do
        raise Anzen::MonitorNameConflictError.new(monitor.name) if @monitors.key?(monitor.name)

        @monitors[monitor.name] = monitor
        @violations_count[monitor.name] = 0
      end
    end

    # Unregister a monitor
    #
    # @param name [String] monitor name
    # @raise [MonitorNotFoundError] if monitor not found
    # @raise [InvalidMonitorError] if monitor is currently enabled
    def unregister(name)
      @mutex.synchronize do
        raise Anzen::MonitorNotFoundError.new(name) unless @monitors.key?(name)

        if @enabled_monitors.include?(name)
          raise Anzen::InvalidMonitorError.new("Cannot unregister enabled monitor '#{name}'")
        end

        @monitors.delete(name)
        @violations_count.delete(name)
      end
    end

    # Get monitor by name
    #
    # @param name [String] monitor name
    # @return [Anzen::Monitor] monitor instance
    # @raise [MonitorNotFoundError] if monitor not found
    def get(name)
      @mutex.synchronize do
        raise Anzen::MonitorNotFoundError.new(name) unless @monitors.key?(name)

        @monitors[name]
      end
    end

    # List all registered monitors
    #
    # @return [Array<Anzen::Monitor>] all monitors
    def list
      @mutex.synchronize do
        @monitors.values.dup
      end
    end

    # List enabled monitors
    #
    # @return [Array<Anzen::Monitor>] enabled monitors
    def list_enabled
      @mutex.synchronize do
        @enabled_monitors.map { |name| @monitors[name] }.dup
      end
    end

    # Enable a monitor by name
    #
    # @param name [String] monitor name
    # @raise [MonitorNotFoundError] if monitor not found
    def enable(name)
      @mutex.synchronize do
        raise Anzen::MonitorNotFoundError.new(name) unless @monitors.key?(name)

        monitor = @monitors[name]
        monitor.enable
        @enabled_monitors.add(name)
      end
    end

    # Disable a monitor by name
    #
    # @param name [String] monitor name
    # @raise [MonitorNotFoundError] if monitor not found
    def disable(name)
      @mutex.synchronize do
        raise Anzen::MonitorNotFoundError.new(name) unless @monitors.key?(name)

        monitor = @monitors[name]
        monitor.disable
        @enabled_monitors.delete(name)
      end
    end

    # Run all enabled monitors' checks
    #
    # Calls check! on each enabled monitor in order.
    # Raises first violation immediately (fail-fast).
    #
    # @return [nil]
    # @raise [ViolationError] subclass on first violation detected
    # @raise [CheckFailedError] on infrastructure failure
    def check_all!
      enabled = @mutex.synchronize { @enabled_monitors.dup }

      enabled.each do |name|
        monitor = @mutex.synchronize { @monitors[name] }
        monitor.check!
      end

      nil
    end

    # Return status of all monitors
    #
    # @return [Hash] aggregated status with keys:
    #   - monitors (Array): status of each monitor
    #   - enabled_count (Integer): number of enabled monitors
    #   - violations_total (Integer): total violations across all monitors
    def status
      @mutex.synchronize do
        monitor_statuses = @monitors.values.map(&:status)
        enabled_count = @enabled_monitors.size
        violations_total = @monitors.values.sum { |m| m.status[:violations] }

        {
          monitors: monitor_statuses,
          enabled_count: enabled_count,
          violations_total: violations_total
        }
      end
    end

    private

    # Validate monitor implements required interface
    #
    # @param monitor [Object] monitor to validate
    # @raise [InvalidMonitorError] if monitor doesn't implement interface
    def validate_monitor_interface(monitor)
      required_methods = %i[name enable disable enabled? check! status to_cli]

      required_methods.each do |method|
        next if monitor.respond_to?(method)

        raise Anzen::InvalidMonitorError.new(
          "Monitor must implement ##{method} method"
        )
      end
    end
  end
end
