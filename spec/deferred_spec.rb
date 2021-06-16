# frozen_string_literal: true

require 'iopromise'
require 'iopromise/deferred'

RSpec.describe IOPromise::Deferred do
  it "leaves the promise pending initially" do
    deferred = IOPromise::Deferred.new { 123 }
    
    expect(deferred).to be_pending
  end

  it "executes the deferred block when the promise is sync'ed" do
    deferred = IOPromise::Deferred.new { 123 }
    
    expect(deferred).to be_pending
    deferred.sync
    expect(deferred).to_not be_pending
    expect(deferred).to be_fulfilled
    expect(deferred.value).to eq(123)
  end

  it "allows for an exception that rejects the promise" do
    deferred = IOPromise::Deferred.new { raise 'oops' }
    
    expect(deferred).to be_pending
    expect { deferred.sync }.to raise_exception('oops')
    expect(deferred).to_not be_pending
    expect(deferred).to be_rejected
  end

  it "executes the deferred block on all pending deferred promises" do
    deferred = IOPromise::Deferred.new { 123 }
    deferred2 = IOPromise::Deferred.new { 456 }
    
    expect(deferred).to be_pending
    expect(deferred2).to be_pending
    deferred.sync
    expect(deferred).to_not be_pending
    expect(deferred2).to_not be_pending
    expect(deferred.value).to eq(123)
    expect(deferred2.value).to eq(456)
  end

  it "allows instrumentation hooks" do
    begin_called = 0
    finish_called = 0
    begin_cb = proc { begin_called += 1 }
    finish_cb = proc { finish_called += 1 }

    deferred = IOPromise::Deferred.new { 123 }
    deferred.instrument(begin_cb, finish_cb)

    expect(begin_called).to eq(0)
    expect(finish_called).to eq(0)

    deferred.sync

    expect(begin_called).to eq(1)
    expect(finish_called).to eq(1)
  end
end
