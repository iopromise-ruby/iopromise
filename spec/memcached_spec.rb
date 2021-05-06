# frozen_string_literal: true

require 'iopromise/memcached'

RSpec.describe IOPromise::Memcached do
  around(:each) do |test|
    ::IOPromise::ExecutorContext.push
    test.run
    ::IOPromise::ExecutorContext.pop
  end

  it "returns a pending promise for a get_as_promise request" do
    client = IOPromise::Memcached.new
    
    p = client.get_as_promise('foo')
    expect(p).to be_pending
  end

  it "can retrieve a value from memcached" do
    raw_client = ::Memcached::Client.new
    client = IOPromise::Memcached.new

    raw_client.set('foo', 'bar')
    
    p = client.get_as_promise('foo')
    p.sync
    expect(p).to_not be_pending
    expect(p).to be_fulfilled
    expect(p.value).to eq('bar')
  end

  it "can be constructed by copying all details from a normal client" do
    raw_client = ::Memcached::Client.new
    client = IOPromise::Memcached.new(raw_client)

    raw_client.set('foo', 'bar')
    
    p = client.get_as_promise('foo')
    p.sync
    expect(p).to_not be_pending
    expect(p).to be_fulfilled
    expect(p.value).to eq('bar')
  end

  it "can retrieve multiple values from memcached concurrently" do
    raw_client = ::Memcached::Client.new
    client = IOPromise::Memcached.new

    raw_client.set('foo', 'bar')
    raw_client.set('test', 'another')
    
    p1 = client.get_as_promise('foo')
    p2 = client.get_as_promise('test')
    p3 = client.get_as_promise('unknown')
    expect(p1).to be_pending
    expect(p2).to be_pending
    expect(p3).to be_pending

    # once we run one, they will all run together
    Promise.all([p1, p2, p3]).sync

    expect(p1).to_not be_pending
    expect(p1).to be_fulfilled
    expect(p1.value).to eq('bar')

    expect(p2).to_not be_pending
    expect(p2).to be_fulfilled
    expect(p2.value).to eq('another')

    expect(p3).to_not be_pending
    expect(p3).to be_fulfilled
    expect(p3.value).to eq(nil)
  end

  it "batches multiple concurrent gets from memcached" do
    raw_client = ::Memcached::Client.new
    client = IOPromise::Memcached.new

    raw_client.set('foo', 'bar')
    raw_client.set('test', 'another')
    
    p1 = client.get_as_promise('foo')
    p2 = client.get_as_promise('test')
    p3 = client.get_as_promise('unknown')
    expect(p1).to be_pending
    expect(p2).to be_pending
    expect(p3).to be_pending

    expect_any_instance_of(Memcached::Client).to receive(:begin_get_multi).with(['foo', 'test', 'unknown'])
    expect_any_instance_of(Memcached::Client).to receive(:continue_get_multi).and_return([{}, [], []])
    p1.sync
  end

  it "handles connection errors as rejections" do
    client = IOPromise::Memcached.new('127.0.0.1:1111')

    p = client.get_as_promise('foo')
    expect { p.sync }.to raise_exception(::Memcached::ConnectionFailure)
    expect(p).to_not be_pending
    expect(p).to be_rejected
  end

  it "batches a series of 'ticks' of multiple concurrent gets from memcached" do
    client = IOPromise::Memcached.new
    
    p1 = client.get_as_promise('foo')
    p2 = client.get_as_promise('test')
    p3 = client.get_as_promise('unknown')

    p1_t = p1.then do
      client.get_as_promise('foo-2')
    end
    p2_t = p2.then do
      client.get_as_promise('test-2')
    end
    p3_t = p3.then do
      client.get_as_promise('unknown-2')
    end
    expect(p1).to be_pending
    expect(p2).to be_pending
    expect(p3).to be_pending
    expect(p1_t).to be_pending
    expect(p2_t).to be_pending
    expect(p3_t).to be_pending

    expect_any_instance_of(Memcached::Client).to receive(:begin_get_multi).with(['foo', 'test', 'unknown'])
    expect_any_instance_of(Memcached::Client).to receive(:continue_get_multi).and_return([{'foo': 'bar', 'test': 'another'}, [], []])
    p1.sync

    expect_any_instance_of(Memcached::Client).to receive(:begin_get_multi).with(['foo-2', 'test-2', 'unknown-2'])
    expect_any_instance_of(Memcached::Client).to receive(:continue_get_multi).and_return([{'foo-2': 'bar', 'test-2': 'another'}, [], []])
    p1_t.sync
  end

  it "batches multiple concurrent gets from memcached, across clients, but in separate 'ticks'" do
    client = IOPromise::Memcached.new
    client2 = IOPromise::Memcached.new

    underlying_client = client.instance_variable_get('@client')
    underlying_client2 = client2.instance_variable_get('@client')
    
    p1 = client.get_as_promise('foo')
    p2 = client.get_as_promise('test')
    p3 = client.get_as_promise('unknown')

    p1_t = p1.then do
      client2.get_as_promise('foo-2')
    end
    p2_t = p2.then do
      client2.get_as_promise('test-2')
    end
    p3_t = p3.then do
      client2.get_as_promise('unknown-2')
    end
    expect(p1).to be_pending
    expect(p2).to be_pending
    expect(p3).to be_pending
    expect(p1_t).to be_pending
    expect(p2_t).to be_pending
    expect(p3_t).to be_pending

    expect(underlying_client).to receive(:begin_get_multi).with(['foo', 'test', 'unknown'])
    expect(underlying_client).to receive(:continue_get_multi).and_return([{'foo': 'bar', 'test': 'another'}, [], []])
    p1.sync

    expect(underlying_client2).to receive(:begin_get_multi).with(['foo-2', 'test-2', 'unknown-2'])
    expect(underlying_client2).to receive(:continue_get_multi).and_return([{'foo-2': 'bar', 'test-2': 'another'}, [], []])
    p1_t.sync
  end
end
