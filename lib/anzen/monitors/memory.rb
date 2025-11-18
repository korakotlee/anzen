# frozen_string_literal: true

module Anzen
  module Monitors
    # Monitor that samples process RSS and raises when usage exceeds a limit.
    # Sampling is synchronous and triggered through #check! to keep the
    # implementation deterministic for specs and CLI output.
    class MemoryMonitor
      include Anzen::Monitor

      DEFAULT_SAMPLING_INTERVAL_MS = 100
      DEFAULT_LIMIT_MB = 512

      attr_reader :name, :limit_mb, :sampling_interval_ms,
                  :last_check_time, :current_rss_mb, :violation_count

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

      def enable
        @enabled = true
        true
      end

      def disable
        @enabled = false
        false
      end

      def enabled?
        @enabled
      end

      def check!
        return nil unless @enabled
        return nil unless should_check?

        rss_mb = read_process_memory_mb
        @current_rss_mb = rss_mb
        @last_check_time = Time.now

        return nil unless @current_rss_mb > @limit_mb

        @violation_count += 1
        raise Anzen::MemoryLimitExceeded.new(@current_rss_mb, @limit_mb)
      rescue Anzen::MemoryLimitExceeded
        raise
      rescue StandardError => e
        raise Anzen::CheckFailedError.new(name, 'Failed to read process memory', e)
      end

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

      def to_cli
        state = @enabled ? 'enabled' : 'disabled'
        "Memory monitor (#{state}): limit=#{@limit_mb}MB, current=#{@current_rss_mb}MB, violations=#{@violation_count}"
      end

      private

      def validate_configuration!
        unless @limit_mb.is_a?(Integer) && @limit_mb.positive?
          raise Anzen::ConfigurationError, "limit_mb must be a positive integer, got: #{@limit_mb.inspect}"
        end

        return if @sampling_interval_ms.is_a?(Integer) && @sampling_interval_ms >= 0

        raise Anzen::ConfigurationError,
              "sampling_interval_ms must be a non-negative integer, got: #{@sampling_interval_ms.inspect}"
      end

      def should_check?
        return false unless @enabled
        return true if @last_check_time.nil?

        elapsed_ms = (Time.now - @last_check_time) * 1000
        elapsed_ms >= @sampling_interval_ms
      end

      def read_process_memory_mb
        pid = Process.pid
        return read_memory_from_proc(pid) if File.exist?("/proc/#{pid}/status")

        read_memory_from_ps(pid)
      end

      def read_memory_from_proc(pid)
        status_file = "/proc/#{pid}/status"
        content = File.read(status_file)
        match = content.match(/^VmRSS:\s+(\d+)\s+kB/)
        raise "Could not find VmRSS in #{status_file}" unless match

        match[1].to_i / 1024.0
      end

      def read_memory_from_ps(pid)
        output, status = run_ps_command(pid)
        raise "ps command failed: #{status.exitstatus}" unless status.success?

        lines = output.strip.split("\n")
        raise "ps output incomplete for PID #{pid}" if lines.length < 2

        fields = lines[1].strip.split
        raise "ps output format unexpected: #{lines[1]}" if fields.length < 2

        fields[1].to_i / 1024.0
      end

      def run_ps_command(pid)
        output = `ps -o pid,rss -p #{pid} 2>/dev/null`
        [output, $?]
      end
    end
  end
end
