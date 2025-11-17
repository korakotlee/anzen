# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Recursion Protection Integration' do
  before do
    # Reset Anzen state
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)
  end

  describe 'end-to-end recursion detection' do
    it 'detects recursion and raises RecursionLimitExceeded' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 30 } }
      }
      Anzen.setup(config: config)

      def deep_recursive_call(depth)
        return Anzen.check! if depth <= 0

        deep_recursive_call(depth - 1)
      end

      expect do
        deep_recursive_call(40)
      end.to raise_error(Anzen::RecursionLimitExceeded) do |error|
        expect(error.current_depth).to be > 30
        expect(error.threshold).to eq(30)
      end
    end

    it 'includes current depth in error' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 20 } }
      }
      Anzen.setup(config: config)

      def recursive_with_depth_check(depth)
        return Anzen.check! if depth <= 0

        recursive_with_depth_check(depth - 1)
      end

      expect do
        recursive_with_depth_check(25)
      end.to raise_error(Anzen::RecursionLimitExceeded) do |error|
        expect(error.current_depth).to be_a(Integer)
        expect(error.current_depth).to be > 0
      end
    end

    it 'includes threshold in error' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 25 } }
      }
      Anzen.setup(config: config)

      def recursive_check_threshold(depth)
        return Anzen.check! if depth <= 0

        recursive_check_threshold(depth - 1)
      end

      expect do
        recursive_check_threshold(35)
      end.to raise_error(Anzen::RecursionLimitExceeded) do |error|
        expect(error.threshold).to eq(25)
      end
    end

    it 'allows application to remain stable after exception' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 20 } }
      }
      Anzen.setup(config: config)

      def risky_recursion(depth)
        return Anzen.check! if depth <= 0

        risky_recursion(depth - 1)
      end

      # First call raises
      expect do
        risky_recursion(25)
      end.to raise_error(Anzen::RecursionLimitExceeded)

      # Application should still work after exception - check status and registry
      expect(Anzen.status).to have_key(:monitors)
      expect(Anzen.status[:monitors]).not_to be_empty
    end

    it 'disables recursion protection when disabled' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 10 } }
      }
      Anzen.setup(config: config)

      Anzen.disable('recursion')

      def unchecked_recursion(depth)
        return Anzen.check! if depth <= 0

        unchecked_recursion(depth - 1)
      end

      # Should not raise because check! is disabled
      expect do
        unchecked_recursion(100)
      end.not_to raise_error
    end

    it 'enables recursion protection when re-enabled' do
      config = {
        enabled_monitors: [],
        monitors: { recursion: { depth_limit: 20 } }
      }
      Anzen.setup(config: config)

      # Initially disabled
      Anzen.enable('recursion')

      def re_enabled_recursion(depth)
        return Anzen.check! if depth <= 0

        re_enabled_recursion(depth - 1)
      end

      # Now it should raise
      expect do
        re_enabled_recursion(25)
      end.to raise_error(Anzen::RecursionLimitExceeded)
    end

    it 'detects indirect recursion (A -> B -> C -> A)' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 25 } }
      }
      Anzen.setup(config: config)

      def indirect_a(depth)
        return Anzen.check! if depth <= 0

        indirect_b(depth - 1)
      end

      def indirect_b(depth)
        indirect_c(depth)
      end

      def indirect_c(depth)
        indirect_a(depth - 1)
      end

      # Should detect the indirect recursion pattern
      expect do
        indirect_a(30)
      end.to raise_error(Anzen::RecursionLimitExceeded)
    end

    it 'supports different depth limits for different use cases' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 500 } }
      }
      Anzen.setup(config: config)

      def safe_recursion(depth)
        return Anzen.check! if depth <= 0

        safe_recursion(depth - 1)
      end

      # This should NOT raise (deep recursion allowed with large limit)
      expect do
        safe_recursion(40)
      end.not_to raise_error

      # Disable and re-enable with different limit
      Anzen.disable('recursion')
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      config2 = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 100 } }
      }
      Anzen.setup(config: config2)

      def tighter_recursion(depth)
        return Anzen.check! if depth <= 0

        tighter_recursion(depth - 1)
      end

      # This SHOULD raise (depth 60 > 100 is false, so use 150 > 100)
      expect do
        tighter_recursion(150)
      end.to raise_error(Anzen::RecursionLimitExceeded) do |error|
        expect(error.threshold).to eq(100)
      end
    end
  end

  describe 'recursion protection status' do
    it 'reports correct status after checks' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 20 } }
      }
      Anzen.setup(config: config)

      def status_check_recursion(depth)
        return Anzen.check! if depth <= 0

        status_check_recursion(depth - 1)
      end

      # Trigger a violation
      expect do
        status_check_recursion(25)
      end.to raise_error(Anzen::RecursionLimitExceeded)

      # Check status reflects the violation
      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }

      expect(recursion_status[:enabled]).to be(true)
      expect(recursion_status[:violations]).to eq(1)
      expect(recursion_status[:thresholds][:depth_limit]).to eq(20)
    end

    it 'tracks multiple violations' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 15 } }
      }
      Anzen.setup(config: config)

      def multi_violation_recursion(depth)
        return Anzen.check! if depth <= 0

        multi_violation_recursion(depth - 1)
      end

      # Trigger first violation
      expect do
        multi_violation_recursion(20)
      end.to raise_error(Anzen::RecursionLimitExceeded)

      status1 = Anzen.status
      recursion_status1 = status1[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_status1[:violations]).to eq(1)

      # Trigger second violation
      expect do
        multi_violation_recursion(20)
      end.to raise_error(Anzen::RecursionLimitExceeded)

      status2 = Anzen.status
      recursion_status2 = status2[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_status2[:violations]).to eq(2)
    end
  end

  describe 'recursion protection initialization' do
    it 'uses default depth_limit when not configured' do
      config = { enabled_monitors: ['recursion'] }
      Anzen.setup(config: config)

      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }

      expect(recursion_status[:thresholds][:depth_limit]).to eq(1000)
    end

    it 'uses configured depth_limit' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 500 } }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }

      expect(recursion_status[:thresholds][:depth_limit]).to eq(500)
    end

    it 'respects enabled_monitors configuration' do
      config = {
        enabled_monitors: [],
        monitors: { recursion: { depth_limit: 20 } }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }

      expect(recursion_status[:enabled]).to be(false)
    end
  end
end
