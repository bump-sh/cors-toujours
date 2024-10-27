require 'rspec'
require 'rack/test'
require 'webmock/rspec'
require_relative '../proxy_server'
require 'jwt'

SECRET_KEY = 'your-secret-key'

describe 'ProxyServer' do
  include Rack::Test::Methods

  def app
    ProxyServer
  end

  let(:valid_token) { JWT.encode({ data: 'test' }, SECRET_KEY, 'HS256') }
  let(:invalid_token) { 'invalid.token.here' }
  let(:target_url) { 'https://jsonplaceholder.typicode.com/posts' }

  # Mock external requests with WebMock or a similar tool (if desired)

  before(:each) do
    stub_request(:get, "https://jsonplaceholder.typicode.com/posts").
      to_return(status: 200, body: "", headers: {})
    stub_request(:put, "https://jsonplaceholder.typicode.com/posts/1").
      to_return(status: 200, body: {title: "updated title"}.to_json, headers: {})
    stub_request(:post, "https://jsonplaceholder.typicode.com/posts").
      to_return(status: 201, body: {title: "foo", body: "bar", userId: 1}.to_json, headers: {})
  end

  context 'when x-bump-jwt-token is present' do
    it 'returns 200 for a valid token' do
      header 'x-bump-jwt-token', valid_token
      get "/proxy?url=#{target_url}"

      expect(last_response.status).to eq(200)
    end

    it 'returns 401 for an invalid token' do
      header 'x-bump-jwt-token', invalid_token
      get "/proxy?url=#{target_url}"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)['error']).to eq('Invalid token')
    end
  end

  context 'when x-bump-jwt-token is missing' do
    it 'returns 401 Unauthorized' do
      get "/proxy?url=#{target_url}"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)['error']).to eq('x-bump-jwt-token header is missing')
    end
  end

  context 'request forwarding' do
    it 'forwards headers and body for POST requests' do
      header 'x-bump-jwt-token', valid_token
      header 'Content-Type', 'application/json'
      post "/proxy?url=#{target_url}", { title: 'foo', body: 'bar', userId: 1 }.to_json

      expect(last_response.status).to eq(201)  # Expect created status if target server responds as expected
      response_body = JSON.parse(last_response.body)
      expect(response_body['title']).to eq('foo')
      expect(response_body['body']).to eq('bar')
      expect(response_body['userId']).to eq(1)
    end

    it 'forwards headers and body for PUT requests' do
      header 'x-bump-jwt-token', valid_token
      header 'Content-Type', 'application/json'
      put "/proxy?url=#{target_url}/1", { id: 1, title: 'updated title' }.to_json

      expect(last_response.status).to eq(200)  # Expect OK status if target server responds as expected
      response_body = JSON.parse(last_response.body)
      expect(response_body['title']).to eq('updated title')
    end
  end
end
