# frozen_string_literal: true

require 'iopromise'

RSpec.describe IOPromise::CancelContext do
  it "cancels IOPromises that are pending after a CancelContext expires" do
    deferred = nil
    chained = nil

    IOPromise::CancelContext.with_new_context do
      deferred = IOPromise::Deferred.new { 123 }
      chained = deferred.then { 456 }

      expect(deferred).to be_pending
      expect(deferred).to_not be_cancelled
      expect(chained).to be_pending
      expect(chained).to_not be_cancelled
    end

    expect(deferred).to be_pending
    expect(deferred).to be_cancelled
    expect(chained).to be_pending
    expect(chained).to_not be_cancelled
  end

  it "cancels IOPromises that are pending after a nested CancelContext expires" do
    deferred = nil
    deferred2 = nil

    IOPromise::CancelContext.with_new_context do
      deferred = IOPromise::Deferred.new { 123 }

      expect(deferred).to be_pending
      expect(deferred).to_not be_cancelled

      IOPromise::CancelContext.with_new_context do
        deferred2 = IOPromise::Deferred.new { 123 }
  
        expect(deferred2).to be_pending
        expect(deferred2).to_not be_cancelled
      end

      expect(deferred2).to be_pending
      expect(deferred2).to be_cancelled
      expect(deferred).to_not be_cancelled
    end

    expect(deferred).to be_pending
    expect(deferred).to be_cancelled
  end

  it "cancels IOPromises when a CancelContext block fails" do
    deferred = nil

    expect {
      IOPromise::CancelContext.with_new_context do
        deferred = IOPromise::Deferred.new { 123 }
  
        expect(deferred).to be_pending
        expect(deferred).to_not be_cancelled
  
        raise 'fail'
      end
    }.to raise_error /fail/

    expect(deferred).to be_pending
    expect(deferred).to be_cancelled
  end
end
