# frozen_string_literal: true

require 'spec_helper'
require 'anzen/monitors/memory'

RSpec.describe Anzen::Monitors::MemoryMonitor do
  subject(:monitor) { described_class.new(limit_mb: 100, sampling_interval_ms: 50) }

  describe 'initialization' do
    it 'creates monitor with valid limit_mb' do
      m = described_class.new(limit_mb: 512)
      expect(m.limit_mb).to eq(512)
      expect(m.enabled?).to be(false)
    end

    it 'raises ConfigurationError for negative limit_mb' do
      expect do
        described_class.new(limit_mb: -1)
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError for zero limit_mb' do
      expect do
        described_class.new(limit_mb: 0)
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError for non-integer limit_mb' do
      expect do
        described_class.new(limit_mb: 5.5)
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError for string limit_mb' do
      expect do
        described_class.new(limit_mb: '100')
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'creates monitor with valid sampling_interval_ms' do
      m = described_class.new(sampling_interval_ms: 200)
      expect(m.sampling_interval_ms).to eq(200)
    end

    it 'raises ConfigurationError for negative sampling_interval_ms' do
      expect do
        described_class.new(sampling_interval_ms: -1)
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError for non-integer sampling_interval_ms' do
      expect do
        described_class.new(sampling_interval_ms: 5.5)
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'initializes disabled by default' do
      expect(monitor.enabled?).to be(false)
    end

    it 'initializes violation count to zero' do
      expect(monitor.violation_count).to eq(0)
    end

    it 'initializes last_check_time to nil' do
      expect(monitor.last_check_time).to be_nil
    end

    it 'initializes current_rss_mb to zero' do
      expect(monitor.current_rss_mb).to eq(0.0)
    end

    it 'uses default values when not specified' do
      m = described_class.new
      expect(m.limit_mb).to eq(512)
      expect(m.sampling_interval_ms).to eq(100)
    end
  end

  describe '#name' do
    it 'returns "memory"' do
      expect(monitor.name).to eq('memory')
    end
  end

  describe '#enable' do
    it 'returns true' do
      expect(monitor.enable).to be(true)
    end

    it 'enables the monitor' do
      monitor.enable
      expect(monitor.enabled?).to be(true)
    end
  end

  describe '#disable' do
    it 'returns false' do
      expect(monitor.disable).to be(false)
    end

    it 'disables the monitor' do
      monitor.enable
      monitor.disable
      expect(monitor.enabled?).to be(false)
    end
  end

  describe '#enabled?' do
    it 'returns false when disabled' do
      expect(monitor.enabled?).to be(false)
    end

    it 'returns true when enabled' do
      monitor.enable
      expect(monitor.enabled?).to be(true)
    end
  end

  describe '#check!' do
    context 'when monitor is disabled' do
      it 'does nothing' do
        expect { monitor.check! }.not_to raise_error
      end

      it 'returns nil' do
        expect(monitor.check!).to be_nil
      end

      it 'does not update last_check_time' do
        monitor.check!
        expect(monitor.last_check_time).to be_nil
      end

      it 'does not update current_rss_mb' do
        monitor.check!
        expect(monitor.current_rss_mb).to eq(0.0)
      end
    end

    context 'when monitor is enabled' do
      before { monitor.enable }

      it 'returns nil when memory is within limit' do
        # Mock low memory usage
        allow(monitor).to receive(:read_process_memory_mb).and_return(50.0)
        expect(monitor.check!).to be_nil
      end

      it 'sets last_check_time on first check' do
        allow(monitor).to receive(:read_process_memory_mb).and_return(50.0)
        monitor.check!
        expect(monitor.last_check_time).to be_a(Time)
      end

      it 'updates current_rss_mb on check' do
        allow(monitor).to receive(:read_process_memory_mb).and_return(75.5)
        monitor.check!
        expect(monitor.current_rss_mb).to eq(75.5)
      end

      it 'raises MemoryLimitExceeded when memory exceeds limit' do
        allow(monitor).to receive(:read_process_memory_mb).and_return(150.0)

        expect do
          monitor.check!
        end.to raise_error(Anzen::MemoryLimitExceeded) do |error|
          expect(error.current_memory_mb).to eq(150.0)
          expect(error.threshold_mb).to eq(100)
        end
      end

      it 'increments violation_count on violation' do
        allow(monitor).to receive(:read_process_memory_mb).and_return(150.0)

        expect do
          monitor.check!
        end.to raise_error(Anzen::MemoryLimitExceeded)

        expect(monitor.violation_count).to eq(1)
      end

      it 'skips check if sampling interval not elapsed' do
        # First check
        allow(monitor).to receive(:read_process_memory_mb).and_return(50.0)
        monitor.check!
        first_check_time = monitor.last_check_time

        # Second check immediately after (should skip)
        allow(monitor).to receive(:read_process_memory_mb).and_return(200.0) # Would violate
        monitor.check!

        # Should not have updated because check was skipped
        expect(monitor.last_check_time).to eq(first_check_time)
        expect(monitor.current_rss_mb).to eq(50.0)
      end

      it 'performs check after sampling interval elapses' do
        # First check
        allow(monitor).to receive(:read_process_memory_mb).and_return(50.0)
        monitor.check!
        first_check_time = monitor.last_check_time

        # Wait for sampling interval to elapse
        sleep(0.06) # 60ms > 50ms interval

        # Second check should execute
        allow(monitor).to receive(:read_process_memory_mb).and_return(80.0)
        monitor.check!

        expect(monitor.current_rss_mb).to eq(80.0)
        expect(monitor.last_check_time).to be > first_check_time
      end

      it 'raises CheckFailedError when memory reading fails' do
        allow(monitor).to receive(:read_process_memory_mb).and_raise(StandardError.new('read failed'))

        expect do
          monitor.check!
        end.to raise_error(Anzen::CheckFailedError) do |error|
          expect(error.monitor_name).to eq('memory')
          expect(error.reason).to eq('Failed to read process memory')
          expect(error.original_error).to be_a(StandardError)
        end
      end

      it 'does not increment violation_count on CheckFailedError' do
        allow(monitor).to receive(:read_process_memory_mb).and_raise(StandardError.new('read failed'))

        expect do
          monitor.check!
        end.to raise_error(Anzen::CheckFailedError)

        expect(monitor.violation_count).to eq(0)
      end
    end
  end

  describe '#status' do
    before { monitor.enable }

    it 'returns hash with required keys' do
      allow(monitor).to receive(:read_process_memory_mb).and_return(50.0)
      monitor.check!

      status = monitor.status
      expect(status).to have_key(:name)
      expect(status).to have_key(:enabled)
      expect(status).to have_key(:thresholds)
      expect(status).to have_key(:last_check)
      expect(status).to have_key(:violations)
    end

    it 'includes monitor name' do
      expect(monitor.status[:name]).to eq('memory')
    end

    it 'includes enabled state' do
      expect(monitor.status[:enabled]).to be(true)
      monitor.disable
      expect(monitor.status[:enabled]).to be(false)
    end

    it 'includes limit_mb threshold' do
      expect(monitor.status[:thresholds][:limit_mb]).to eq(100)
    end

    it 'includes last_check timestamp' do
      expect(monitor.status[:last_check]).to be_nil

      allow(monitor).to receive(:read_process_memory_mb).and_return(50.0)
      monitor.check!
      expect(monitor.status[:last_check]).to be_a(Time)
    end

    it 'includes violation count' do
      expect(monitor.status[:violations]).to eq(0)

      allow(monitor).to receive(:read_process_memory_mb).and_return(150.0)
      expect { monitor.check! }.to raise_error(Anzen::MemoryLimitExceeded)
      expect(monitor.status[:violations]).to eq(1)
    end
  end

  describe '#to_cli' do
    it 'returns a string' do
      expect(monitor.to_cli).to be_a(String)
    end

    it 'includes monitor name' do
      expect(monitor.to_cli).to include('Memory monitor')
    end

    it 'includes enabled/disabled status' do
      expect(monitor.to_cli).to include('disabled')
      monitor.enable
      expect(monitor.to_cli).to include('enabled')
    end

    it 'includes memory limit' do
      expect(monitor.to_cli).to include('limit=100MB')
    end

    it 'includes current memory usage' do
      expect(monitor.to_cli).to include('current=0.0MB')
    end

    it 'includes violation count' do
      expect(monitor.to_cli).to include('violations=0')
    end

    it 'is single line' do
      expect(monitor.to_cli).not_to include("\n")
    end

    it 'updates current memory in CLI output after check' do
      monitor.enable
      allow(monitor).to receive(:read_process_memory_mb).and_return(75.5)
      monitor.check!

      cli_output = monitor.to_cli
      expect(cli_output).to include('current=75.5MB')
    end
  end

  describe 'interface compliance' do
    it 'includes Monitor module' do
      expect(monitor.is_a?(Anzen::Monitor)).to be(true)
    end

    it 'responds to all required methods' do
      expect(monitor).to respond_to(:name)
      expect(monitor).to respond_to(:enable)
      expect(monitor).to respond_to(:disable)
      expect(monitor).to respond_to(:enabled?)
      expect(monitor).to respond_to(:check!)
      expect(monitor).to respond_to(:status)
      expect(monitor).to respond_to(:to_cli)
    end
  end

  describe 'memory reading' do
    it 'reads memory from /proc when available' do
      monitor = described_class.new
      pid = Process.pid

      # Mock /proc file existence and content
      allow(File).to receive(:exist?).with("/proc/#{pid}/status").and_return(true)
      allow(File).to receive(:read).with("/proc/#{pid}/status").and_return("VmRSS:    102400 kB\n")

      memory_mb = monitor.send(:read_process_memory_mb)
      expect(memory_mb).to eq(100.0) # 102400 KB = 100 MB
    end

    it 'falls back to ps command when /proc not available' do
      monitor = described_class.new
      pid = Process.pid

      # Mock /proc not available
      allow(File).to receive(:exist?).with("/proc/#{pid}/status").and_return(false)

      # Mock ps command output: header + data line
      ps_output = "  PID   RSS\n#{pid} 204800\n"
      mock_status = double('Process::Status', success?: true)
      allow(monitor).to receive(:run_ps_command).with(pid).and_return([ps_output, mock_status])

      memory_mb = monitor.send(:read_process_memory_mb)
      expect(memory_mb).to eq(200.0) # 204800 KB = 200 MB
    end

    it 'raises error when /proc VmRSS not found' do
      monitor = described_class.new
      pid = Process.pid

      allow(File).to receive(:exist?).with("/proc/#{pid}/status").and_return(true)
      allow(File).to receive(:read).with("/proc/#{pid}/status").and_return("Some other content\n")

      expect do
        monitor.send(:read_process_memory_mb)
      end.to raise_error(/Could not find VmRSS/)
    end

    it 'raises error when ps command fails' do
      monitor = described_class.new
      pid = Process.pid

      allow(File).to receive(:exist?).with("/proc/#{pid}/status").and_return(false)
      mock_status = double('Process::Status', success?: false, exitstatus: 1)
      allow(monitor).to receive(:run_ps_command).with(pid).and_return(['', mock_status])

      expect do
        monitor.send(:read_process_memory_mb)
      end.to raise_error(/ps command failed/)
    end

    it 'raises error when ps output is incomplete' do
      monitor = described_class.new
      pid = Process.pid

      allow(File).to receive(:exist?).with("/proc/#{pid}/status").and_return(false)
      ps_output = "  PID   RSS\n"
      mock_status = double('Process::Status', success?: true)
      allow(monitor).to receive(:run_ps_command).with(pid).and_return([ps_output, mock_status])

      expect do
        monitor.send(:read_process_memory_mb)
      end.to raise_error(/ps output incomplete/)
    end
  end
end
