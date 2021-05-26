# frozen_string_literal: true

require 'iopromise/dalli'

RSpec.describe IOPromise::Dalli do
  around(:each) do |test|
    ::IOPromise::ExecutorContext.push
    test.run
    ::IOPromise::ExecutorContext.pop
  end

  it "returns a pending promise for a get request" do
    client = IOPromise::Dalli.new('localhost:11211')
    
    p = client.get('foo')
    expect(p).to be_pending
  end

  it "can retrieve a value from memcached" do
    raw_client = ::Dalli::Client.new('localhost:11211')
    client = IOPromise::Dalli.new('localhost:11211')

    raw_client.set('foo', 'bar')
    
    p = client.get('foo')
    p.sync
    expect(p).to_not be_pending
    expect(p).to be_fulfilled
    response = p.value
    expect(response).to be_exist
    expect(response.key).to eq('foo')
    expect(response.value).to eq('bar')
  end

  it "can retrieve multiple values from memcached concurrently" do
    raw_client = ::Dalli::Client.new('localhost:11211')
    client = IOPromise::Dalli.new('localhost:11211')

    raw_client.set('foo', 'bar')
    raw_client.set('test', 'another')
    
    p1 = client.get('foo')
    p2 = client.get('test')
    p3 = client.get('unknown')
    expect(p1).to be_pending
    expect(p2).to be_pending
    expect(p3).to be_pending

    # once we run one, they will all run together
    Promise.all([p1, p2, p3]).sync

    expect(p1).to_not be_pending
    expect(p1).to be_fulfilled
    expect(p1.value).to be_exist
    expect(p1.value.key).to eq('foo')
    expect(p1.value.value).to eq('bar')

    expect(p2).to_not be_pending
    expect(p2).to be_fulfilled
    expect(p2.value).to be_exist
    expect(p2.value.key).to eq('test')
    expect(p2.value.value).to eq('another')

    expect(p3).to_not be_pending
    expect(p3).to be_fulfilled
    expect(p3.value).to_not be_exist
    expect(p3.value.key).to eq('unknown')
    expect(p3.value.value).to eq(nil)
  end

  it "handles complete connection errors as rejections" do
    client = IOPromise::Dalli.new('127.0.0.1:1111')

    p = client.get('foo')
    expect { p.sync }.to raise_exception(::Dalli::RingError)
    expect(p).to_not be_pending
    expect(p).to be_rejected
  end

  it "handles single node failures gracefully" do
    client = IOPromise::Dalli.new(['127.0.0.1:1111', '127.0.0.1:11211'])

    (0..100).each do |i|
      p = client.get("foo-#{i}")
      p.sync
      expect(p).to_not be_pending
      expect(p).to be_fulfilled
    end
  end

  it "pipelines requests in the order they are created when possible" do
    client = IOPromise::Dalli.new('localhost:11211')

    promises = [
      client.set('hello', 'something'),
      client.get('hello'),
      client.set('hello', 'another'),
      client.get('hello'),
      client.set('hello', 'pipelined'),
      client.get('hello'),
    ]
    
    # we only ask to wait on the last one ...
    promises.last.sync

    # ... but since the others were pipelined in first, they will execute first.
    expect(promises[0]).to be_fulfilled
    expect(promises[1]).to be_fulfilled
    expect(promises[2]).to be_fulfilled
    expect(promises[3]).to be_fulfilled
    expect(promises[4]).to be_fulfilled
    expect(promises[5]).to be_fulfilled

    # stores should have all succeeded
    expect(promises[1].value.value).to eq('something')
    expect(promises[3].value.value).to eq('another')
    expect(promises[5].value.value).to eq('pipelined')
  end

  it "doesn't block pipelined requests if a value is pending" do
    client = IOPromise::Dalli.new('localhost:11211')

    evil = Promise.new

    promises = [
      client.set('hello', 'something'),
      client.get('hello'),
      client.set('hello', evil),
      client.get('hello'),
      client.set('hello', 'pipelined'),
      client.get('hello'),
    ]
    
    # we only ask to wait on the last one ...
    promises.last.sync

    # ... but since the others were pipelined in first, they will execute first.
    expect(promises[0]).to be_fulfilled
    expect(promises[1]).to be_fulfilled
    expect(promises[2]).to_not be_fulfilled
    expect(promises[3]).to be_fulfilled
    expect(promises[4]).to be_fulfilled
    expect(promises[5]).to be_fulfilled

    # stores should have all succeeded
    expect(promises[1].value.value).to eq('something')
    expect(promises[3].value.value).to eq('something')
    expect(promises[5].value.value).to eq('pipelined')

    # finalising the value for the set should then run it
    evil.fulfill('better late than never')

    Promise.all(promises).sync

    expect(promises[2]).to be_fulfilled

    response = client.get('hello').sync
    expect(response).to be_exist
    expect(response.value).to eq('better late than never')
  end

  it "supports deleting keys" do
    client = IOPromise::Dalli.new('localhost:11211')

    response = client.set('hello', 'something').sync
    expect(response).to be_stored

    response = client.get('hello').sync
    expect(response).to be_exist
    expect(response.value).to eq('something')

    response = client.delete('hello').sync
    expect(response).to be_stored

    response = client.get('hello').sync
    expect(response).to_not be_exist
  end

  it "supports appending and prepending keys" do
    client = IOPromise::Dalli.new('localhost:11211')

    response = client.set('someraw', 'something', nil, :raw => true).sync
    expect(response).to be_stored

    response = client.get('someraw').sync
    expect(response).to be_exist
    expect(response.value).to eq('something')

    response = client.append('someraw', ' else').sync
    expect(response).to be_stored

    response = client.get('someraw').sync
    expect(response).to be_exist
    expect(response.value).to eq('something else')

    response = client.prepend('someraw', 'yet again ').sync
    expect(response).to be_stored

    response = client.get('someraw').sync
    expect(response).to be_exist
    expect(response.value).to eq('yet again something else')
  end

  it "supports incr and decr keys" do
    client = IOPromise::Dalli.new('localhost:11211')

    response = client.set('someint', '1', nil, :raw => true).sync
    expect(response).to be_stored

    response = client.get('someint').sync
    expect(response).to be_exist
    expect(response.value).to eq('1')

    response = client.incr('someint', 1).sync
    expect(response).to be_stored
    expect(response.value).to eq(2)

    response = client.get('someint').sync
    expect(response).to be_exist
    expect(response.value).to eq('2')

    response = client.incr('someint', 2).sync
    expect(response).to be_stored
    expect(response.value).to eq(4)

    response = client.get('someint').sync
    expect(response).to be_exist
    expect(response.value).to eq('4')

    response = client.decr('someint', 1).sync
    expect(response).to be_stored
    expect(response.value).to eq(3)

    response = client.get('someint').sync
    expect(response).to be_exist
    expect(response.value).to eq('3')
  end

  it "supports fetch with no existing value" do
    client = IOPromise::Dalli.new('localhost:11211')

    client.delete('fetch').sync

    p = client.fetch('fetch') do
      'computed value'
    end

    response = p.sync
    expect(response).to eq('computed value') # fetch unwraps!

    response = client.get('fetch').sync
    expect(response).to be_exist
    expect(response.value).to eq('computed value')
  end

  it "supports fetch with an existing value" do
    client = IOPromise::Dalli.new('localhost:11211')

    client.set('fetch', 'hello').sync

    p = client.fetch('fetch') do
      'computed value'
    end

    response = p.sync
    expect(response).to eq('hello') # fetch unwraps!

    response = client.get('fetch').sync
    expect(response).to be_exist
    expect(response.value).to eq('hello')
  end

  it "times out queries" do
    client = IOPromise::Dalli.new('localhost:11211')

    expect(IO).to receive(:select).exactly(3).times do
      sleep(0.4)
      [[], [], []]
    end

    p = client.set('timeout', 'hello')
    expect { p.sync }.to raise_exception(::Timeout::Error)
    expect(p).to_not be_pending
    expect(p).to be_rejected
  end
end
