# frozen_string_literal: true

RSpec.describe IOPromise::ExecutorContext do
  class DeferredInAnotherPoolPromise < IOPromise::Deferred::DeferredPromise
    def initialize(pool_key = nil, &block)
      @pool_key = pool_key
      super(&block)
    end

    def execute_pool
      IOPromise::Deferred::DeferredExecutorPool.for(@pool_key)
    end
  end

  it "allows registering new executor pools during resolution" do
    p = DeferredInAnotherPoolPromise.new 'foo' do
      'foo'
    end
    pt = p.then do |result|
      DeferredInAnotherPoolPromise.new 'bar' do
        DeferredInAnotherPoolPromise.new 'baz' do
          'baz'
        end
      end
    end
    expect(pt.sync).to eq('baz')
  end
end
