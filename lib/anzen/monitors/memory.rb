# frozen_string_literal: true

module Anzen
  module Monitors
    # Monitor that detects memory consumption exceeding configurable threshold
    #
    # Monitors process RSS (Resident Set Size) memory usage with configurable sampling
    # to minimize overhead. Supports absolute MB limits or percentage of available memory.
    # Raises MemoryLimitExceeded immediately when threshold is exceeded.
    #
    # Use case: Prevent memory leaks and runaway memory consumption in long-running processes
    #
    # @api public
    # @example Basic usage
    #   monitor = Anzen::Monitors::MemoryMonitor.new(limit_mb: 512)
    #   monitor.enable
    #   monitor.check!  # Raises MemoryLimitExceeded if > 512MB used
    class MemoryMonitor
      include Anzen::Monitor

      # Default sampling interval in milliseconds
      DEFAULT_SAMPLING_INTERVAL_MS = 100

      # Default memory limit in MB
      DEFAULT_LIMIT_MB = 512

      # @return [String] monitor name
      attr_reader :name

      # @return [Integer] memory limit in MB
      attr_reader :limit_mb

      # @return [Integer] sampling interval in milliseconds
      attr_reader :sampling_interval_ms

      # @return [Time, nil] timestamp of last check
      attr_reader :last_check_time

      # @return [Float] current RSS memory in MB at last check
      attr_reader :current_rss_mb

      # @return [Integer] count of violations detected
      attr_reader :violation_count

      # Initialize MemoryMonitor
      #
      # @param limit_mb [Integer] memory limit in MB (default: 512)
      # @param sampling_interval_ms [Integer] milliseconds between checks (default: 100)
      def initialize(limit_mb: DEFAULT_LIMIT_MB, sampling_interval_ms: DEFAULT_SAMPLING_INTERVAL_MS)
        @name = 'memory'
        @enabled = false
        @limit_mb = limit_mb
        @sampling_interval_ms = sampling_interval_ms
        @last_check_time = nil
        @current_rss_mb = 0.0
        @violation_count = 0

        validate_configuration!
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

      # Check for memory limit violation
      #
      # Reads current process RSS memory and compares to configured limit.
      # Only performs check if sampling interval has elapsed since last check.
      # Raises MemoryLimitExceeded if memory usage exceeds threshold.
      # Does nothing if monitor is disabled.
      #
      # @return [nil]
      # @raise [Anzen::MemoryLimitExceeded] if memory usage exceeds threshold
      # @raise [Anzen::CheckFailedError] if memory reading fails
      def check!
        return nil unless @enabled

        begin
          if should_check?
            @current_rss_mb = read_process_memory_mb
            @last_check_time = Time.now

            if @current_rss_mb > @limit_mb
              @violation_count += 1
              raise Anzen::MemoryLimitExceeded.new(@current_rss_mb, @limit_mb)
            end
          end

          nil
        rescue Anzen::MemoryLimitExceeded
          raise
        rescue StandardError => e
          raise Anzen::CheckFailedError.new(name, 'Failed to read process memory', e)
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
            limit_mb: @limit_mb,
            sampling_interval_ms: @sampling_interval_ms
          },
          last_check: @last_check_time,
          violations: @violation_count
        }
      end

      # Return human-readable one-liner for CLI
      #
      # @return [String]
      def to_cli
        status_text = @enabled ? 'enabled' : 'disabled'
        "Memory monitor (#{status_text}): limit=#{@limit_mb}MB, current=#{@current_rss_mb.round(1)}MB, violations=#{@violation_count}"
      end

      private

      # Validate configuration parameters
      #
      # @raise [Anzen::ConfigurationError] if configuration is invalid
      def validate_configuration!
        unless @limit_mb.is_a?(Integer) && @limit_mb > 0
          raise Anzen::ConfigurationError, "limit_mb must be a positive integer, got: #{@limit_mb.inspect}"
        end

        return if @sampling_interval_ms.is_a?(Integer) && @sampling_interval_ms >= 0

        raise Anzen::ConfigurationError,
              "sampling_interval_ms must be a non-negative integer, got: #{@sampling_interval_ms.inspect}"
      end

      # Check if enough time has elapsed since last check
      #
      # @return [Boolean] true if should perform check
      def should_check?
        return true if @last_check_time.nil?

        elapsed_ms = (Time.now - @last_check_time) * 1000
        elapsed_ms >= @sampling_interval_ms
      end

      # Read current process memory usage in MB
      #
      # Attempts to read RSS from /proc/[pid]/status (Linux) or falls back to
      # parsing `ps` command output for cross-platform compatibility.
      #
      # @return [Float] memory usage in MB
      # @raise [StandardError] if memory reading fails
      def read_process_memory_mb
        pid = Process.pid

        # Try Linux /proc filesystem first (most efficient)
        return read_memory_from_proc(pid) if File.exist?("/proc/#{pid}/status")

        # Fallback to ps command (cross-platform)
        read_memory_from_ps(pid)
      end

      # Read memory from Linux /proc/[pid]/status
      #
      # @param pid [Integer] process ID
      # @return [Float] memory in MB
      def read_memory_from_proc(pid)
        status_file = "/proc/#{pid}/status"
        content = File.read(status_file)

        # Find VmRSS line: "VmRSS:    12345 kB"
        vmrss_match = content.match(/^VmRSS:\s+(\d+)\s+kB/)
        raise "Could not find VmRSS in #{status_file}" unless vmrss_match

        kb = vmrss_match[1].to_i
        kb / 1024.0 # Convert to MB
      end

      # Read memory using ps command (fallback for non-Linux systems)
      #
      # @param pid [Integer] process ID
      # @return [Float] memory in MB
      def read_memory_from_ps(pid)
        # Use ps to get RSS in KB, then convert to MB
        # Format: "PID RSS" where RSS is in KB
        output, status = run_ps_command(pid)
        raise "ps command failed: #{status.exitstatus}" unless status.success?

        lines = output.strip.split("\n")
        raise "ps output incomplete for PID #{pid}" if lines.length < 2

        # Second line contains the data
        fields = lines[1].strip.split
        raise "ps output format unexpected: #{lines[1]}" if fields.length < 2

        rss_kb = fields[1].to_i
        rss_kb / 1024.0 # Convert to MB
      end

      # Execute ps command (extracted for testability)
      #
      # @param pid [Integer] process ID
      # @return [Array<String, Process::Status>] output and status
      def run_ps_command(pid)
        output = `ps -o pid,rss -p #{pid} 2>/dev/null`
        [output, $?]
      end
    end
  end
end
