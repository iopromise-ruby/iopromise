# frozen_string_literal: true

RSpec.describe IOPromise::Base do
  # Implement the very minimal requirements of an IOPromise::Base subclass
  class DummyExecutorPool < IOPromise::ExecutorPool::Sequential
  end
  class DummyPromise < IOPromise::Base
    def execute_pool
      DummyExecutorPool.for(Thread.current)
    end
  end

  it "fulfills like a normal promise" do
    b = DummyPromise.new
    chained = b.then { |v| v }
    expect(b).to be_pending
    expect(chained).to be_pending

    b.fulfill('test')

    expect(b).to_not be_pending
    expect(b).to be_fulfilled
    expect(b.value).to eq('test')

    expect(chained).to_not be_pending
    expect(chained).to be_fulfilled
    expect(chained.value).to eq('test')
  end

  it "rejects like a normal promise" do
    b = DummyPromise.new
    chained = b.then { |v| v }
    expect(b).to be_pending
    expect(chained).to be_pending

    b.reject('test')

    expect(b).to_not be_pending
    expect(b).to be_rejected
    expect(b.reason).to eq('test')

    expect(chained).to_not be_pending
    expect(chained).to be_rejected
    expect(chained.reason).to eq('test')
  end

  context "#cancel" do
    it "prevents handlers on fulfill" do
      b = DummyPromise.new
      chained = b.then { |v| v }
      expect(b).to be_pending
      expect(chained).to be_pending
      expect(b).to_not be_cancelled

      b.cancel

      expect(b).to be_cancelled

      b.fulfill('test')

      expect(b).to be_pending
      expect(chained).to be_pending
    end

    it "prevents handlers on reject" do
      b = DummyPromise.new
      chained = b.then { |v| v }
      expect(b).to be_pending
      expect(chained).to be_pending
      expect(b).to_not be_cancelled

      b.cancel

      expect(b).to be_cancelled

      b.reject('test')

      expect(b).to be_pending
      expect(chained).to be_pending
    end

    it "prevents successful promise chains after cancel" do
      b = DummyPromise.new
      b.cancel

      expect(b).to be_cancelled

      chained = b.then { |v| v }

      b.fulfill('test')

      expect(b).to be_pending
      expect(chained).to be_pending
    end

    it "prevents failing promise chains after cancel" do
      b = DummyPromise.new
      b.cancel

      expect(b).to be_cancelled

      chained = b.rescue { |v| v }

      b.reject('test')

      expect(b).to be_pending
      expect(chained).to be_pending
    end

    it "does nothing on completed promises" do
      b = DummyPromise.new
      b.fulfill('foo')

      expect(b).to_not be_pending
      expect(b).to be_fulfilled
      expect(b).to_not be_cancelled

      b.cancel

      expect(b).to_not be_pending
      expect(b).to be_fulfilled
      expect(b).to_not be_cancelled
    end

    it "allows Promise#then to work if already resolved" do
      b = DummyPromise.new
      b.fulfill('foo')

      expect(b).to_not be_pending
      expect(b).to be_fulfilled
      expect(b).to_not be_cancelled

      b.cancel

      chained = b.then { |v| v }
      expect(chained.value).to eq('foo')
    end
  end
end
