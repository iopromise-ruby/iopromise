# frozen_string_literal: true

RSpec.describe IOPromise::Base do
  it "fulfills like a normal promise" do
    b = IOPromise::Base.new
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
    b = IOPromise::Base.new
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
      b = IOPromise::Base.new
      chained = b.then { |v| v }
      expect(b).to be_pending
      expect(chained).to be_pending
      expect(b).to_not be_cancelled

      b.cancel

      expect(b).to be_cancelled

      b.fulfill('test')

      expect(b).to_not be_pending
      expect(b).to be_fulfilled
      expect(b.value).to eq('test')

      expect(chained).to be_pending
    end

    it "prevents handlers on reject" do
      b = IOPromise::Base.new
      chained = b.then { |v| v }
      expect(b).to be_pending
      expect(chained).to be_pending
      expect(b).to_not be_cancelled

      b.cancel

      expect(b).to be_cancelled

      b.reject('test')

      expect(b).to_not be_pending
      expect(b).to be_rejected
      expect(b.reason).to eq('test')

      expect(chained).to be_pending
    end

    it "does nothing on completed promises" do
      b = IOPromise::Base.new
      b.fulfill('foo')

      expect(b).to_not be_pending
      expect(b).to be_fulfilled
      expect(b).to_not be_cancelled

      b.cancel

      expect(b).to_not be_pending
      expect(b).to be_fulfilled
      expect(b).to_not be_cancelled
    end
  end
end
