# frozen_string_literal: true

require 'iopromise'
require 'iopromise/deferred'

RSpec.describe IOPromise::Deferred do
  around(:each) do |example|
    IOPromise::CancelContext.with_new_context do
      example.run
    end
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

  it "waiting on a cancelled deferred promise fails rather than blocking" do
    deferred = IOPromise::Deferred.new { 123 }
    deferred.cancel

    expect {
      deferred.wait
    }.to raise_error(IOPromise::CancelledError)
  end

  it "cleans up the deferred promise from the pool on cancellation" do
    deferred = IOPromise::Deferred.new { 123 }
    deferred.cancel

    expect(deferred).to be_pending
    expect(deferred).to be_cancelled

    expect(deferred.execute_pool.instance_variable_get('@pending')).to be_empty
  end

  context "with delay" do
    it "delays execution of a delayed promise" do
      long_deferred = IOPromise::Deferred.new(timeout: 0.5) { 123 }
      expect(long_deferred).to be_pending

      deferred = IOPromise::Deferred.new { 123 }
      expect(long_deferred).to be_pending
      expect(deferred).to be_pending

      deferred.sync

      expect(long_deferred).to be_pending
      expect(deferred).to be_fulfilled
    end

    it "delays execution of concurrent delayed promises with different times" do
      promises = []
      promises << IOPromise::Deferred.new { Time.now }
      promises << IOPromise::Deferred.new(timeout: 0.5) { Time.now }
      promises << IOPromise::Deferred.new(timeout: 1) { Time.now }
      last = IOPromise::Deferred.new(timeout: 2) { Time.now } # create this out of order
      promises << IOPromise::Deferred.new(timeout: 1.5) { Time.now }
      promises << last # we'll expect it to complete last

      Promise.all(promises).sync

      exec_times = promises.map do |p|
        expect(p).to be_fulfilled
        p.value.to_f
      end

      # these should execute in the expected order
      expect(exec_times[0]).to be < exec_times[1]
      expect(exec_times[1]).to be < exec_times[2]
      expect(exec_times[2]).to be < exec_times[3]
      expect(exec_times[3]).to be < exec_times[4]

      # the delay should be at least the 0.5s timeouts specified
      expect(exec_times[1] - exec_times[0]).to be > 0.4
      expect(exec_times[2] - exec_times[1]).to be > 0.4
      expect(exec_times[3] - exec_times[2]).to be > 0.4
      expect(exec_times[4] - exec_times[3]).to be > 0.4
    end

    it "fully empties the pending promise list in the execution pool" do
      Promise.all([
        IOPromise::Deferred.new { Time.now },
        IOPromise::Deferred.new(timeout: 0.5) { Time.now },
      ]).sync

      pending = IOPromise::Deferred::DeferredExecutorPool.for(Thread.current).instance_variable_get(:@pending)
      expect(pending).to be_empty
    end

    context "with deferred-based retries" do
      class FlakeyRPC
        def initialize
          @attempts = 0
        end
  
        def execute
          Promise.resolve.then do
            @attempts = @attempts + 1
            raise "need to retry this, attempts=#{@attempts}!" if @attempts < 4
            "all good on attempt=#{@attempts}"
          end
        end
      end
  
      def retry_promise_block(times, &block)
        promise = block.call
        return promise if times == 0
  
        promise.rescue do |ex|
          IOPromise::Deferred.new(timeout: 0.5) do
            retry_promise_block(times - 1, &block)
          end
        end
      end
  
      it "retries with delays and rejects when it always fails" do
        flakey = FlakeyRPC.new
        failing_flake = retry_promise_block(2) do
          flakey.execute
        end

        start = Time.now
        expect { failing_flake.sync }.to raise_exception /need to retry this, attempts=3/
        duration = Time.now - start
        expect(duration).to be > 1 # 2 retries
        expect(duration).to be < 1.5 # but no more
      end
  
      it "retries with delays and fulfills when the last succeeds" do
        flakey = FlakeyRPC.new
        success_flake = retry_promise_block(5) do
          flakey.execute
        end

        start = Time.now
        result = success_flake.sync
        expect(result).to eq('all good on attempt=4')
        duration = Time.now - start
        expect(duration).to be > 1.5 # 3 retries
        expect(duration).to be < 2 # but not more, should stop at first success
      end
    end
  end
end
