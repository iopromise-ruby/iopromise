# frozen_string_literal: true

require 'iopromise'
require 'iopromise/deferred'

RSpec.describe IOPromise::Deferred do
  around(:each) do |test|
    ::IOPromise::ExecutorContext.push
    test.run
    ::IOPromise::ExecutorContext.pop
  end

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
end
