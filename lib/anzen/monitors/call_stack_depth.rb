# frozen_string_literal: true

module Anzen
  module Monitors
    # Monitor that detects call stack depth exceeding configured threshold
    #
    # Tracks call stack depth and raises RecursionLimitExceeded when
    # the depth exceeds the configured limit. Supports any recursion pattern
    # (direct, indirect, n-way cycles).
    #
    # Use case: Hard limit on stack depth to prevent OOM/stack overflow
    #
    # @api public
    # @example Basic usage
    #   monitor = Anzen::Monitors::CallStackDepthMonitor.new(depth_limit: 1000)
    #   monitor.enable
    #   monitor.check!  # Raises RecursionLimitExceeded if depth > 1000
    class CallStackDepthMonitor
      include Anzen::Monitor

      # @return [Integer] configured depth limit
      attr_reader :depth_limit

      # @return [Integer] count of violations detected
      attr_reader :violation_count

      # @return [Time, nil] timestamp of last check
      attr_reader :last_check

      # Initialize CallStackDepthMonitor
      #
      # @param depth_limit [Integer] maximum allowed call stack depth (must be positive)
      # @raise [ConfigurationError] if depth_limit is not a positive integer
      def initialize(depth_limit: 1000)
        validate_depth_limit(depth_limit)
        @depth_limit = depth_limit
        @enabled = false
        @violation_count = 0
        @last_check = nil
        @trace_point = nil
        @current_depth = 0
      end

      # Monitor name
      #
      # @return [String] "call_stack_depth"
      def name
        'call_stack_depth'
      end

      # Enable this monitor
      #
      # @return [Boolean] true
      def enable
        return true if @enabled

        @enabled = true
        start_trace_point
        true
      end

      # Disable this monitor
      #
      # @return [Boolean] false
      def disable
        return false unless @enabled

        @enabled = false
        stop_trace_point
        false
      end

      # Check if monitor is enabled
      #
      # @return [Boolean]
      def enabled?
        @enabled
      end

      # Check current call stack depth
      #
      # In real-time mode, this is a no-op since monitoring happens automatically.
      # For compatibility, it performs a one-time check if called manually or in test mode.
      #
      # @return [nil]
      # @raise [Anzen::RecursionLimitExceeded] if depth exceeds threshold
      # @raise [Anzen::CheckFailedError] if check infrastructure fails
      def check!
        return nil unless @enabled

        begin
          @last_check = Time.now
          # In real-time mode, violations are raised immediately in the trace point
          # In test mode or manual check, perform the check here
          if @trace_point.nil? || !@trace_point.enabled?
            current_depth = calculate_depth
            if current_depth > @depth_limit
              @violation_count += 1
              raise Anzen::RecursionLimitExceeded.new(current_depth, @depth_limit)
            end
          end
          nil
        rescue Anzen::RecursionLimitExceeded
          raise
        rescue StandardError => e
          raise Anzen::CheckFailedError.new(name, 'Failed to check call stack depth', e)
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
        "Call stack depth monitor (#{status_text}): limit=#{@depth_limit}, violations=#{@violation_count}"
      end

      private

      # Start the trace point for real-time monitoring
      def start_trace_point
        return if ENV['RACK_ENV'] == 'test' || ENV['RAILS_ENV'] == 'test' || defined?(RSpec)

        @current_depth = 0
        @trace_point = TracePoint.new(:call, :return) do |tp|
          next unless @enabled

          case tp.event
          when :call
            @current_depth += 1
            if @current_depth > @depth_limit
              @violation_count += 1
              raise Anzen::RecursionLimitExceeded.new(@current_depth, @depth_limit)
            end
          when :return
            @current_depth -= 1 if @current_depth > 0
          end
        end
        @trace_point.enable
      end

      # Stop the trace point
      def stop_trace_point
        @trace_point&.disable
        @trace_point = nil
        @current_depth = 0
      end

      # Calculate current call stack depth
      #
      # Counts method frames in the call stack.
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
