# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anzen::Monitor do
  subject(:monitor) { Class.new { include Anzen::Monitor }.new }

  %i[name enable disable enabled? check! status to_cli].each do |interface_method|
    it "requires ##{interface_method} to be implemented" do
      expect do
        monitor.public_send(interface_method)
      end.to raise_error(NotImplementedError, /##{interface_method}/)
    end
  end
end
