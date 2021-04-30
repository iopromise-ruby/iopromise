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
end
