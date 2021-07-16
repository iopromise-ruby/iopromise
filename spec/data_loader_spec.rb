# frozen_string_literal: true

require 'iopromise'
require 'iopromise/deferred'
require 'iopromise/data_loader'

RSpec.describe IOPromise::DataLoader do
  class ExampleDataLoader
    include IOPromise::DataLoader

    attr_promised_data :foo
    attr_promised_data :bar

    def initialize(data_source)
      @foo = IOPromise::Deferred.new { data_source[:foo] }
      @bar = IOPromise::Deferred.new { data_source[:bar] }
    end
  end

  class AnotherDataLoader
    include IOPromise::DataLoader

    attr_promised_data :baz

    def initialize(data_source)
      @baz = IOPromise::Deferred.new { data_source[:baz] }
    end
  end

  class BrokenDataLoader
    include IOPromise::DataLoader

    attr_promised_data :broken

    def initialize
      @broken = ::Promise.new
      @broken.reject('rejection reason')
    end
  end

  class ParentDataLoader
    include IOPromise::DataLoader
    attr_promised_data :parent_thing, :example_component, :another_component

    def initialize(data_source)
      @parent_thing = IOPromise::Deferred.new { data_source[:parent_thing] }
      @example_component = ExampleDataLoader.new(data_source)
      @another_component = AnotherDataLoader.new(data_source)
    end
  end

  it "registers the promised data keys for the class" do
    expect(ExampleDataLoader.promised_data_keys).to eq([:foo, :bar])
    expect(AnotherDataLoader.promised_data_keys).to eq([:baz])
    expect(BrokenDataLoader.promised_data_keys).to eq([:broken])
  end

  it "creates attr readers that sync and handle success by returning a value" do
    example = ExampleDataLoader.new({ :foo => 123, :bar => 456 })
    expect(example.foo).to eq(123)
    expect(example.bar).to eq(456)
  end

  it "creates attr readers that sync and handle failure by raising the reason" do
    broken = BrokenDataLoader.new
    expect { broken.broken }.to raise_exception('rejection reason')
  end

  it "provides a data_as_promise which syncs all promises, including chained ones" do
    data_source = {}
    parent = ParentDataLoader.new(data_source)
    example = parent.instance_variable_get('@example_component')
    another = parent.instance_variable_get('@another_component')

    # get our promise data source
    ds_promise = parent.data_as_promise
    expect(parent.instance_variable_get('@parent_thing')).to be_pending
    expect(example.instance_variable_get('@foo')).to be_pending
    expect(example.instance_variable_get('@bar')).to be_pending
    expect(another.instance_variable_get('@baz')).to be_pending

    # set the data source values, just to really make sure this has to have happened after now
    data_source[:foo] = 123
    data_source[:bar] = 456
    data_source[:baz] = 987
    data_source[:parent_thing] = 789

    # sync on the full data tree
    ds_promise.sync
    expect(parent.instance_variable_get('@parent_thing')).to be_fulfilled
    expect(example.instance_variable_get('@foo')).to be_fulfilled
    expect(example.instance_variable_get('@bar')).to be_fulfilled
    expect(another.instance_variable_get('@baz')).to be_fulfilled

    # and finally, the values should have propagated
    expect(parent.parent_thing).to eq(789)
    expect(example.foo).to eq(123)
    expect(example.bar).to eq(456)
    expect(another.baz).to eq(987)
  end
end
