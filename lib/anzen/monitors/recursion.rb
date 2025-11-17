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
      def initialize
        @enabled = false
        @violation_count = 0
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

      # Check for recursion pattern
      #
      # Analyzes the current call stack to detect if any method appears
      # multiple times (direct recursion) or if there's a cycle in the call chain
      # (indirect recursion). Raises RecursionLimitExceeded on first detection.
      # Does nothing if monitor is disabled.
      #
      # @return [nil]
      # @raise [Anzen::RecursionLimitExceeded] if recursion pattern detected
      # @raise [Anzen::CheckFailedError] if check infrastructure fails
      def check!
        return nil unless @enabled

        begin
          if recursion_detected?
            @violation_count += 1
            raise Anzen::RecursionLimitExceeded.new(current_depth, 1)
          end

          nil
        rescue Anzen::RecursionLimitExceeded
          raise
        rescue StandardError => e
          raise Anzen::CheckFailedError.new(name, 'Failed to detect recursion pattern', e)
        end
      end

      # Return current status
      #
      # @return [Hash] status hash with keys: name, enabled, violations
      def status
        {
          name: name,
          enabled: @enabled,
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

      # Get current call stack depth for error reporting
      #
      # @return [Integer]
      def current_depth
        caller.length
      end
    end
  end
end
