# frozen_string_literal: true

module Anzen
  # Base interface/contract for all safety monitors
  #
  # All monitors (built-in and custom) must implement this interface.
  # This module defines the required methods that every monitor must provide.
  #
  # @api public
  # @example Implement a custom monitor
  #   class MyMonitor
  #     include Anzen::Monitor
  #
  #     def name
  #       'my_monitor'
  #     end
  #
  #     def check!
  #       # Your monitoring logic here
  #       raise Anzen::ViolationError.new("violation") if problem_detected?
  #     end
  #   end
  module Monitor
    # Unique identifier for this monitor
    #
    # @return [String] monitor name (format: [a-z0-9_]+)
    def name
      raise NotImplementedError, "#{self.class} must implement #name"
    end

    # Enable this monitor for checking
    #
    # @return [Boolean] true
    def enable
      raise NotImplementedError, "#{self.class} must implement #enable"
    end

    # Disable this monitor from checking
    #
    # @return [Boolean] false
    def disable
      raise NotImplementedError, "#{self.class} must implement #disable"
    end

    # Check if this monitor is currently enabled
    #
    # @return [Boolean] true if enabled, false if disabled
    def enabled?
      raise NotImplementedError, "#{self.class} must implement #enabled?"
    end

    # Execute this monitor's check
    #
    # Reads current state, compares to thresholds, and raises appropriate error if violation detected.
    # Must raise a ViolationError subclass on violation, or CheckFailedError if check itself fails.
    # Must not raise if check passes.
    # Returns nil if check passes (monitor enabled or disabled).
    #
    # @return [nil] if check passes
    # @raise [Anzen::ViolationError] subclass on detection
    # @raise [Anzen::CheckFailedError] on infrastructure failure
    def check!
      raise NotImplementedError, "#{self.class} must implement #check!"
    end

    # Return current status of this monitor
    #
    # @return [Hash] status hash with keys: name, enabled, thresholds, last_check, violations
    #   - name (String): monitor name
    #   - enabled (Boolean): whether monitor is enabled
    #   - thresholds (Hash): monitor-specific threshold values
    #   - last_check (Time): timestamp of last check, or nil if never checked
    #   - violations (Integer): count of violations detected
    def status
      raise NotImplementedError, "#{self.class} must implement #status"
    end

    # Return human-readable one-liner for CLI output
    #
    # @return [String] single line describing monitor status
    def to_cli
      raise NotImplementedError, "#{self.class} must implement #to_cli"
    end
  end
end
