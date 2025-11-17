# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RecursionMonitor Integration' do
  before do
    # Reset Anzen state
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)
  end

  describe 'RecursionMonitor end-to-end' do
    it 'detects direct recursion on first occurrence' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {}
      }
      Anzen.setup(config: config)

      recursive_proc = proc { |depth, was_called|
        Anzen.check! if was_called

        recursive_proc.call(depth - 1, true)
      }

      expect do
        recursive_proc.call(3, false)
      end.to raise_error(Anzen::RecursionLimitExceeded)
    end

    it 'detects recursion through nested calls' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 50 } }
      }
      Anzen.setup(config: config)

      # Direct recursion via a helper to simulate nested call contexts
      def r_helper(depth)
        return Anzen.check! if depth <= 0

        r_helper(depth - 1)
      end

      expect do
        r_helper(3)
      end.to raise_error(Anzen::RecursionLimitExceeded)
    end
  end

  describe 'Selective monitor enablement' do
    it 'allows both monitors when both enabled' do
      config = {
        enabled_monitors: %w[call_stack_depth recursion],
        monitors: { call_stack_depth: { depth_limit: 50 } }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      enabled = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled).to include('call_stack_depth')
      expect(enabled).to include('recursion')
    end

    it 'allows only call_stack_depth when recursion disabled' do
      config = {
        enabled_monitors: ['call_stack_depth'],
        monitors: { call_stack_depth: { depth_limit: 30 } }
      }
      Anzen.setup(config: config)

      def moderate_recursion(depth)
        return Anzen.check! if depth <= 0

        moderate_recursion(depth - 1)
      end

      # Should raise only for depth limit, not for recursion pattern
      expect do
        moderate_recursion(35)
      end.to raise_error(Anzen::RecursionLimitExceeded) do |error|
        expect(error.threshold).to eq(30)
      end
    end

    it 'allows only recursion when call_stack_depth disabled' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { call_stack_depth: { depth_limit: 10 } }
      }
      Anzen.setup(config: config)

      recursive_proc = proc { |depth, first_call|
        Anzen.check! if first_call

        recursive_proc.call(depth - 1, true)
      }

      # Should raise only for recursion pattern
      expect do
        recursive_proc.call(3, false)
      end.to raise_error(Anzen::RecursionLimitExceeded)
    end
  end

  describe 'Status and monitoring' do
    it 'reports both monitors in status' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      status = Anzen.status
      monitor_names = status[:monitors].map { |m| m[:name] }

      expect(monitor_names).to include('call_stack_depth')
      expect(monitor_names).to include('recursion')
    end

    it 'tracks violations for each monitor independently' do
      config = {
        enabled_monitors: ['call_stack_depth'],
        monitors: { call_stack_depth: { depth_limit: 20 } }
      }
      Anzen.setup(config: config)

      def violation_recursion(depth)
        return Anzen.check! if depth <= 0

        violation_recursion(depth - 1)
      end

      # Trigger a call_stack_depth violation
      expect do
        violation_recursion(25)
      end.to raise_error(Anzen::RecursionLimitExceeded)

      status = Anzen.status
      depth_monitor = status[:monitors].find { |m| m[:name] == 'call_stack_depth' }
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }

      expect(depth_monitor[:violations]).to eq(1)
      expect(recursion_monitor[:violations]).to eq(0)
    end
  end

  describe 'Configuration' do
    it 'uses configured depth limits' do
      config = {
        enabled_monitors: [],
        monitors: { call_stack_depth: { depth_limit: 500 } }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      depth_monitor = status[:monitors].find { |m| m[:name] == 'call_stack_depth' }

      expect(depth_monitor[:thresholds][:depth_limit]).to eq(500)
    end

    it 'uses default depth limit when not configured' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      status = Anzen.status
      depth_monitor = status[:monitors].find { |m| m[:name] == 'call_stack_depth' }

      expect(depth_monitor[:thresholds][:depth_limit]).to eq(1000)
    end
  end
end
