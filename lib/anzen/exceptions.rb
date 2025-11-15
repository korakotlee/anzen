# frozen_string_literal: true

module Anzen
  # Base exception for all Anzen errors
  class Error < StandardError; end

  # Base exception for safety violations detected by monitors
  #
  # @api public
  class ViolationError < Error; end

  # Raised when recursion depth exceeds configured threshold
  #
  # @api public
  class RecursionLimitExceeded < ViolationError
    # @return [Integer] current recursion depth when violation detected
    attr_reader :current_depth

    # @return [Integer] configured depth threshold
    attr_reader :threshold

    # Initialize RecursionLimitExceeded exception
    #
    # @param current_depth [Integer] current call stack depth
    # @param threshold [Integer] configured limit
    def initialize(current_depth, threshold)
      @current_depth = current_depth
      @threshold = threshold
      super("Recursion depth (#{current_depth}) exceeded threshold (#{threshold})")
    end
  end

  # Raised when process memory usage exceeds configured threshold
  #
  # @api public
  class MemoryLimitExceeded < ViolationError
    # @return [Integer] current memory usage in MB
    attr_reader :current_memory_mb

    # @return [Integer] configured memory threshold in MB
    attr_reader :threshold_mb

    # Initialize MemoryLimitExceeded exception
    #
    # @param current_memory_mb [Integer] current process memory in MB
    # @param threshold_mb [Integer] configured threshold in MB
    def initialize(current_memory_mb, threshold_mb)
      @current_memory_mb = current_memory_mb
      @threshold_mb = threshold_mb
      super("Memory usage (#{current_memory_mb}MB) exceeded threshold (#{threshold_mb}MB)")
    end
  end

  # Raised when a monitor's check infrastructure fails (not a violation)
  #
  # Used to distinguish infrastructure errors from actual safety violations.
  # For example: cannot read /proc/self/status when checking memory.
  #
  # @api public
  class CheckFailedError < Error
    # @return [String] name of the monitor that failed
    attr_reader :monitor_name

    # @return [String] reason for the check failure
    attr_reader :reason

    # @return [Exception, nil] original exception if available
    attr_reader :original_error

    # Initialize CheckFailedError
    #
    # @param monitor_name [String] name of the monitor that failed
    # @param reason [String] description of what failed
    # @param original_error [Exception, nil] exception from the failed check
    def initialize(monitor_name, reason, original_error = nil)
      @monitor_name = monitor_name
      @reason = reason
      @original_error = original_error

      message = "Monitor '#{monitor_name}' check failed: #{reason}"
      message += " (#{original_error.class}: #{original_error.message})" if original_error
      super(message)
    end
  end

  # Raised when Anzen configuration is invalid
  #
  # @api public
  class ConfigurationError < Error; end

  # Raised when attempting to access a non-existent monitor
  #
  # @api public
  class MonitorNotFoundError < Error
    # @param monitor_name [String] name of monitor that was not found
    def initialize(monitor_name)
      super("Monitor '#{monitor_name}' not found in registry")
    end
  end

  # Raised when attempting to register an invalid monitor
  #
  # @api public
  class InvalidMonitorError < Error
    # @param reason [String] description of what makes monitor invalid
    def initialize(reason)
      super("Invalid monitor: #{reason}")
    end
  end

  # Raised when attempting to register a monitor with a name that already exists
  #
  # @api public
  class MonitorNameConflictError < Error
    # @param monitor_name [String] name that caused conflict
    def initialize(monitor_name)
      super("Monitor name '#{monitor_name}' is already registered")
    end
  end

  # Raised when Anzen.setup is called more than once
  #
  # @api public
  class InitializationError < Error
    # @param reason [String] description of initialization problem
    def initialize(reason = "Anzen already initialized")
      super(reason)
    end
  end
end
