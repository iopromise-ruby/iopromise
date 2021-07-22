# frozen_string_literal: true

require 'iopromise'
require 'iopromise/rack/context_middleware'

RSpec.describe IOPromise::Rack::ContextMiddleware do
  subject { described_class.new(app) }
  let(:request) { Rack::MockRequest.new(subject) }

  context "without any promises" do
    let(:app) { lambda {|env| [200, {'Content-Type' => 'text/plain'}, ['OK']]} }
    
    it "allows requests to complete" do
      response = request.get("/some/path")
      expect(response.status).to eq(200)
    end
  end

  context "with completing and pending IOPromises" do
    let(:req_storage) { {} }
    let(:app) { lambda { |env|
      req_storage[:deferred] = IOPromise::Deferred.new { 123 }
      req_storage[:deferred].sync
      req_storage[:incomplete] = IOPromise::Deferred.new { 123 }
      [200, {'Content-Type' => 'text/plain'}, ['OK']]
    } }
    
    it "allows requests to complete" do
      response = request.get("/some/path")
      expect(response.status).to eq(200)
    end

    it "doesn't touch completed IOPromises" do
      response = request.get("/some/path")
      expect(req_storage[:deferred]).to be_fulfilled
      expect(req_storage[:deferred]).to_not be_cancelled
    end

    it "cancels incomplete IOPromises" do
      response = request.get("/some/path")
      expect(req_storage[:incomplete]).to be_pending
      expect(req_storage[:incomplete]).to be_cancelled
    end
  end
end
