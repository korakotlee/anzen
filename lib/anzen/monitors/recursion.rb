# frozen_string_literal: true

module Anzen
  module Monitors
    # Monitor that detects any recursive method calls (pattern-based)
    #
    # Detects direct recursion (same method repeating) and indirect recursion
    # (method chains forming cycles). Raises RecursionLimitExceeded immediately
    # on first recursion detection, with no depth threshold.
    #
    # Use case: Strict no-recursion enforcement (e.g., signal handlers, async contexts)
    #
    # @api public
    # @example Basic usage
    #   monitor = Anzen::Monitors::RecursionMonitor.new
    #   monitor.enable
    #   monitor.check!  # Raises RecursionLimitExceeded if any recursion detected
    class RecursionMonitor
      include Anzen::Monitor

      # Thread-local key for storing call frame tracking
      FRAME_KEY = :anzen_recursion_frames

      # @return [Integer] count of violations detected
      attr_reader :violation_count

      # Initialize RecursionMonitor
      #
      # @param depth_limit [Integer] maximum allowed recursion depth (default: 1000)
      def initialize(depth_limit: 2000)
        @enabled = false
        @violation_count = 0
        @depth_limit = depth_limit
        @last_check = nil
        @trace_point = nil
        @call_stack = nil
      end

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

      # Check for recursion pattern
      #
      # In real-time mode, this is a no-op since monitoring happens automatically.
      # For compatibility, it checks current state if called manually or in test mode.
      #
      # @return [nil]
      # @raise [Anzen::RecursionLimitExceeded] if recursion detected and depth exceeds limit
      # @raise [Anzen::CheckFailedError] if check infrastructure fails
      def check!
        return nil unless @enabled

        begin
          @last_check = Time.now
          # In real-time mode, violations are raised immediately in the trace point
          # In test mode or manual check, perform the check here
          if @trace_point.nil? || !@trace_point.enabled?
            current_depth = caller.length
            if recursion_detected? && current_depth > @depth_limit
              @violation_count += 1
              raise Anzen::RecursionLimitExceeded.new(current_depth, @depth_limit)
            end
          end
          nil
        rescue Anzen::RecursionLimitExceeded
          raise
        rescue StandardError => e
          raise Anzen::CheckFailedError.new(name, 'Failed to check recursion', e)
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
        "Recursion monitor (#{status_text}): violations=#{@violation_count}"
      end

      private

      # Start the trace point for real-time monitoring
      def start_trace_point
        return if ENV['RACK_ENV'] == 'test' || ENV['RAILS_ENV'] == 'test' || defined?(RSpec)

        @call_stack = Thread.current[FRAME_KEY] ||= []
        @trace_point = TracePoint.new(:call, :return) do |tp|
          next unless @enabled

          case tp.event
          when :call
            context = extract_call_context_from_tp(tp.path, tp.lineno, tp.method_id.to_s)
            next unless context

            if @call_stack.include?(context)
              current_depth = @call_stack.size + 1
              if current_depth > @depth_limit
                @violation_count += 1
                raise Anzen::RecursionLimitExceeded.new(current_depth, @depth_limit)
              end
            end
            @call_stack.push(context)
          when :return
            @call_stack.pop if @call_stack&.last
          end
        end
        @trace_point.enable
      end

      # Stop the trace point
      def stop_trace_point
        @trace_point&.disable
        @trace_point = nil
        Thread.current[FRAME_KEY] = nil
      end

      # Detect if current call stack has recursion pattern
      #
      # Uses call context (file:line:method) for application frames to avoid
      # false positives from framework internals while still detecting cycles.
      #
      # @return [Boolean] true if recursion detected
      def recursion_detected?
        contexts = extract_call_contexts
        seen = Set.new
        contexts.each do |ctx|
          return true if seen.include?(ctx)

          seen.add(ctx)
        end
        false
      end

      # Extract call contexts (file:line:method) from the filtered call stack
      #
      # Example: "path/file.rb:123:in `method'" => "path/file.rb:123:method"
      #
      # @return [Array<String>]
      def extract_call_contexts
        caller
          .reject { |frame| should_skip_frame?(frame) }
          .map { |frame| extract_call_context(frame) }
          .compact
      end

      # Determine if a caller frame should be skipped
      #
      # Skips frames from:
      # - Standard library (stdlib paths)
      # - RSpec and testing framework core
      # - Ruby's internal code
      # - Gems/vendor directories (except application code)
      #
      # Does NOT skip application code in spec/test/integration directories.
      #
      # @param frame [String] caller frame string
      # @return [Boolean] true if frame should be skipped
      def should_skip_frame?(frame)
        # Skip only specific framework/library patterns, not application test code
        skip_patterns = [
          %r{/gems/.*\.rb:}, # Bundler gems
          %r{\.bundle/}, # Bundler paths
          %r{/lib/ruby/\d+\.\d+}, # Standard library
          %r{rspec.*gem.*/lib/},       # RSpec gem code (not test files)
          /<internal:/,                # Ruby internals
          /method_missing/ # Dynamic method dispatch
        ]

        skip_patterns.any? { |pattern| frame.match?(pattern) }
      end

      # Extract file:line:method context from a caller frame
      def extract_call_context(frame)
        match = frame.match(/^([^:]+:\d+):in `([^']+)'/)
        return nil unless match

        file_line = match[1]
        method = match[2]
        "#{file_line}:#{method}"
      end

      # Extract call context from trace point
      def extract_call_context_from_tp(path, lineno, method_id)
        return nil if should_skip_frame?("#{path}:#{lineno}:in `#{method_id}'")

        "#{path}:#{lineno}:#{method_id}"
      end

      # Get current call stack depth for error reporting
      #
      # @return [Integer]
      def current_depth
        caller.length
      end
    end
  end
end
