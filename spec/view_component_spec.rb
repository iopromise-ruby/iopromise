# frozen_string_literal: true

require 'iopromise'
require 'iopromise/deferred'
require 'iopromise/view_component'

require 'action_controller'

RSpec.describe IOPromise::ViewComponent do
  class ExampleComponent < ViewComponent::Base
    include IOPromise::ViewComponent::DataLoader
    attr_async :foo
    attr_async :bar

    def initialize(data_source)
      @foo = IOPromise::Deferred.new { data_source[:foo] }
      @bar = IOPromise::Deferred.new { data_source[:bar] }
    end

    def call
      "ExampleComponent is rendered"
    end
  end

  class AnotherComponent < ViewComponent::Base
    include IOPromise::ViewComponent::DataLoader
    attr_async :baz

    def initialize(data_source)
      @baz = IOPromise::Deferred.new { data_source[:baz] }
    end
  end

  class BrokenComponent < ViewComponent::Base
    include IOPromise::ViewComponent::DataLoader
    attr_async :broken

    def initialize
      @broken = ::Promise.new
      @broken.reject('rejection reason')
    end
  end

  class ParentComponent < ViewComponent::Base
    include IOPromise::ViewComponent::DataLoader
    attr_async :parent_thing
    attr_async :example_component
    attr_async :another_component

    def initialize(data_source)
      @parent_thing = IOPromise::Deferred.new { data_source[:parent_thing] }
      @example_component = ExampleComponent.new(data_source)
      @another_component = AnotherComponent.new(data_source)
    end
  end

  it "registers the promised data keys for the class" do
    expect(ExampleComponent.attr_async_names).to eq([:foo, :bar])
    expect(AnotherComponent.attr_async_names).to eq([:baz])
    expect(BrokenComponent.attr_async_names).to eq([:broken])
  end

  it "creates attr readers that sync and handle success by returning a value" do
    example = ExampleComponent.new({ :foo => 123, :bar => 456 })
    expect(example.foo).to eq(123)
    expect(example.bar).to eq(456)
  end

  it "creates attr readers that sync and handle failure by raising the reason" do
    broken = BrokenComponent.new
    expect { broken.broken }.to raise_exception('rejection reason')
  end

  it "provides a async_attributes which syncs all promises, including chained ones" do
    data_source = {}
    parent = ParentComponent.new(data_source)
    example = parent.instance_variable_get('@example_component')
    another = parent.instance_variable_get('@another_component')

    # get our promise data source
    ds_promise = parent.async_attributes
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

  it "ensures that async_attributes is synced before render" do
    example = ExampleComponent.new({ :foo => 123, :bar => 456 })
    ds = example.async_attributes

    expect(ds).to be_pending

    out = ActionController::Base.render(example)
    # we intentionally don't use either of the template vars here, since that would force sync
    expect(out).to eq('ExampleComponent is rendered')

    expect(ds).to_not be_pending
    expect(example.instance_variable_get('@foo')).to_not be_pending
    expect(example.instance_variable_get('@bar')).to_not be_pending
  end
end
