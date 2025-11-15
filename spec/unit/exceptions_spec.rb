# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Anzen Exceptions' do
  describe Anzen::Error do
    it 'inherits from StandardError' do
      expect(Anzen::Error.superclass).to eq(StandardError)
    end

    it 'can be instantiated and raised' do
      expect { raise Anzen::Error, 'test' }.to raise_error(Anzen::Error)
    end
  end

  describe Anzen::ViolationError do
    it 'inherits from Error' do
      expect(Anzen::ViolationError.superclass).to eq(Anzen::Error)
    end

    it 'can be caught as a ViolationError' do
      expect { raise Anzen::ViolationError, 'violation' }.to raise_error(Anzen::ViolationError)
    end

    it 'can be caught as a generic Error' do
      expect { raise Anzen::ViolationError, 'violation' }.to raise_error(Anzen::Error)
    end
  end

  describe Anzen::RecursionLimitExceeded do
    it 'inherits from ViolationError' do
      expect(Anzen::RecursionLimitExceeded.superclass).to eq(Anzen::ViolationError)
    end

    it 'stores current depth and threshold' do
      error = Anzen::RecursionLimitExceeded.new(1234, 1000)
      expect(error.current_depth).to eq(1234)
      expect(error.threshold).to eq(1000)
    end

    it 'generates descriptive message' do
      error = Anzen::RecursionLimitExceeded.new(1234, 1000)
      expect(error.message).to eq('Recursion depth (1234) exceeded threshold (1000)')
    end

    it 'can be raised and caught' do
      expect { raise Anzen::RecursionLimitExceeded.new(500, 400) }.to raise_error(Anzen::RecursionLimitExceeded)
    end
  end

  describe Anzen::MemoryLimitExceeded do
    it 'inherits from ViolationError' do
      expect(Anzen::MemoryLimitExceeded.superclass).to eq(Anzen::ViolationError)
    end

    it 'stores current memory and threshold' do
      error = Anzen::MemoryLimitExceeded.new(2048, 1024)
      expect(error.current_memory_mb).to eq(2048)
      expect(error.threshold_mb).to eq(1024)
    end

    it 'generates descriptive message' do
      error = Anzen::MemoryLimitExceeded.new(2048, 1024)
      expect(error.message).to eq('Memory usage (2048MB) exceeded threshold (1024MB)')
    end

    it 'can be raised and caught' do
      expect { raise Anzen::MemoryLimitExceeded.new(2048, 1024) }.to raise_error(Anzen::MemoryLimitExceeded)
    end
  end

  describe Anzen::CheckFailedError do
    it 'inherits from Error' do
      expect(Anzen::CheckFailedError.superclass).to eq(Anzen::Error)
    end

    it 'is NOT a ViolationError' do
      error = Anzen::CheckFailedError.new('test_monitor', 'reason')
      expect(error).not_to be_a(Anzen::ViolationError)
    end

    it 'stores monitor name and reason' do
      error = Anzen::CheckFailedError.new('my_monitor', 'cannot read /proc')
      expect(error.monitor_name).to eq('my_monitor')
      expect(error.reason).to eq('cannot read /proc')
    end

    it 'generates message with monitor name and reason' do
      error = Anzen::CheckFailedError.new('my_monitor', 'cannot read /proc')
      expect(error.message).to include('my_monitor')
      expect(error.message).to include('cannot read /proc')
    end

    it 'optionally stores original error' do
      original = RuntimeError.new('original problem')
      error = Anzen::CheckFailedError.new('my_monitor', 'reason', original)
      expect(error.original_error).to eq(original)
    end

    it 'includes original error in message when present' do
      original = RuntimeError.new('original problem')
      error = Anzen::CheckFailedError.new('my_monitor', 'reason', original)
      expect(error.message).to include('RuntimeError')
      expect(error.message).to include('original problem')
    end

    it 'can be raised and caught' do
      expect { raise Anzen::CheckFailedError.new('test', 'reason') }.to raise_error(Anzen::CheckFailedError)
    end
  end

  describe Anzen::ConfigurationError do
    it 'inherits from Error' do
      expect(Anzen::ConfigurationError.superclass).to eq(Anzen::Error)
    end

    it 'can be instantiated with message' do
      error = Anzen::ConfigurationError.new('invalid config')
      expect(error.message).to eq('invalid config')
    end
  end

  describe Anzen::MonitorNotFoundError do
    it 'inherits from Error' do
      expect(Anzen::MonitorNotFoundError.superclass).to eq(Anzen::Error)
    end

    it 'includes monitor name in message' do
      error = Anzen::MonitorNotFoundError.new('my_monitor')
      expect(error.message).to include('my_monitor')
      expect(error.message).to include('not found')
    end
  end

  describe Anzen::InvalidMonitorError do
    it 'inherits from Error' do
      expect(Anzen::InvalidMonitorError.superclass).to eq(Anzen::Error)
    end

    it 'includes reason in message' do
      error = Anzen::InvalidMonitorError.new('missing enable method')
      expect(error.message).to include('missing enable method')
    end
  end

  describe Anzen::MonitorNameConflictError do
    it 'inherits from Error' do
      expect(Anzen::MonitorNameConflictError.superclass).to eq(Anzen::Error)
    end

    it 'includes monitor name in message' do
      error = Anzen::MonitorNameConflictError.new('duplicate_name')
      expect(error.message).to include('duplicate_name')
      expect(error.message).to include('already registered')
    end
  end

  describe Anzen::InitializationError do
    it 'inherits from Error' do
      expect(Anzen::InitializationError.superclass).to eq(Anzen::Error)
    end

    it 'has default message' do
      error = Anzen::InitializationError.new
      expect(error.message).to include('already initialized')
    end

    it 'supports custom reason' do
      error = Anzen::InitializationError.new('custom reason')
      expect(error.message).to eq('custom reason')
    end
  end

  describe 'exception hierarchy' do
    it 'catches ViolationError with its subclasses' do
      violations = [
        Anzen::RecursionLimitExceeded.new(100, 50),
        Anzen::MemoryLimitExceeded.new(2048, 1024)
      ]

      violations.each do |violation|
        expect { raise violation }.to raise_error(Anzen::ViolationError)
      end
    end

    it 'does NOT catch CheckFailedError as ViolationError' do
      error = Anzen::CheckFailedError.new('test', 'reason')
      begin
        raise error
      rescue Anzen::ViolationError
        raise 'CheckFailedError should not be caught as ViolationError'
      rescue Anzen::CheckFailedError
        # Expected
      end
    end

    it 'catches all Anzen errors as Error' do
      errors = [
        Anzen::ViolationError.new('violation'),
        Anzen::RecursionLimitExceeded.new(100, 50),
        Anzen::MemoryLimitExceeded.new(2048, 1024),
        Anzen::CheckFailedError.new('test', 'reason'),
        Anzen::ConfigurationError.new('config'),
        Anzen::MonitorNotFoundError.new('test'),
        Anzen::InvalidMonitorError.new('reason'),
        Anzen::MonitorNameConflictError.new('test'),
        Anzen::InitializationError.new('reason')
      ]

      errors.each do |error|
        expect { raise error }.to raise_error(Anzen::Error)
      end
    end
  end
end
