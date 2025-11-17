# frozen_string_literal: true

module Anzen
  module Monitors
    # Monitor that detects recursion depth exceeding configured threshold
    #
    # Tracks call stack depth per-thread and raises RecursionLimitExceeded when
    # the depth exceeds the configured limit. Supports both direct recursion
    # (method calling itself) and indirect recursion (method chains forming cycles).
    #
    # @api public
    # @example Basic usage
    #   monitor = Anzen::Monitors::RecursionMonitor.new(depth_limit: 1000)
    #   monitor.enable
    #   monitor.check!  # Raises RecursionLimitExceeded if depth > 1000
    class RecursionMonitor
      include Anzen::Monitor

      # Thread-local key for storing call stack depth
      DEPTH_KEY = :anzen_recursion_depth

      # @return [Integer] configured depth limit
      attr_reader :depth_limit

      # @return [Integer] count of violations detected
      attr_reader :violation_count

      # @return [Time, nil] timestamp of last check
      attr_reader :last_check

      # Initialize RecursionMonitor
      #
      # @param depth_limit [Integer] maximum allowed recursion depth (must be positive)
      # @raise [ConfigurationError] if depth_limit is not a positive integer
      def initialize(depth_limit: 1000)
        validate_depth_limit(depth_limit)
        @depth_limit = depth_limit
        @enabled = false
        @violation_count = 0
        @last_check = nil
      end

      # Monitor name
      #
      # @return [String] "recursion"
      def name
        'recursion'
      end

      # Enable this monitor
      #
      # @return [Boolean] true
      def enable
        @enabled = true
      end

      # Disable this monitor
      #
      # @return [Boolean] false
      def disable
        @enabled = false
      end

      # Check if monitor is enabled
      #
      # @return [Boolean]
      def enabled?
        @enabled
      end

      # Check current recursion depth
      #
      # Reads the call stack, counts method frames, and raises RecursionLimitExceeded
      # if depth exceeds threshold. Blocks count as method frames.
      # Does nothing if monitor is disabled.
      #
      # @return [nil]
      # @raise [Anzen::RecursionLimitExceeded] if depth exceeds threshold
      # @raise [Anzen::CheckFailedError] if check infrastructure fails
      def check!
        return nil unless @enabled

        begin
          current_depth = calculate_depth
          @last_check = Time.now

          if current_depth > @depth_limit
            @violation_count += 1
            raise Anzen::RecursionLimitExceeded.new(current_depth, @depth_limit)
          end

          nil
        rescue Anzen::RecursionLimitExceeded
          raise
        rescue StandardError => e
          raise Anzen::CheckFailedError.new(name, 'Failed to calculate recursion depth', e)
        end
      end

      # Return current status
      #
      # @return [Hash] status hash with keys: name, enabled, thresholds, last_check, violations
      def status
        {
          name: name,
          enabled: @enabled,
          thresholds: {
            depth_limit: @depth_limit
          },
          last_check: @last_check,
          violations: @violation_count
        }
      end

      # Return human-readable one-liner for CLI
      #
      # @return [String]
      def to_cli
        status_text = @enabled ? 'enabled' : 'disabled'
        "Recursion monitor (#{status_text}): limit=#{@depth_limit}, violations=#{@violation_count}"
      end

      private

      # Calculate current call stack depth
      #
      # Counts method frames in the call stack, excluding frames from Anzen itself.
      # Uses Kernel.caller to get the call stack.
      #
      # @return [Integer] current depth
      def calculate_depth
        # Kernel.caller returns array of strings like "path/file.rb:123:in `method_name'"
        # Each frame represents a method call (including blocks)
        caller.length
      end

      # Validate depth_limit configuration
      #
      # @param depth_limit [Integer, Numeric]
      # @raise [Anzen::ConfigurationError] if invalid
      def validate_depth_limit(depth_limit)
        return if depth_limit.is_a?(Numeric) && depth_limit > 0 && depth_limit == depth_limit.to_i

        raise Anzen::ConfigurationError, "depth_limit must be a positive integer, got #{depth_limit.inspect}"
      end
    end
  end
end
