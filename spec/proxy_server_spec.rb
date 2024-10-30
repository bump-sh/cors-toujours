require "rspec"
require "rack/test"
require "webmock/rspec"
require_relative "../proxy_server"
require "dotenv/load"
require "jwt"

PRIVATE_KEY = ENV.fetch("JWT_SIGNING_PRIVATE_KEY").gsub("\\n", "\n")

describe "ProxyServer" do
  include Rack::Test::Methods

  def app
    ProxyServer
  end

  def expect_header(k, v)
    expect(last_response.headers[k]).to eq v
  end

  let(:valid_token) do
    private_key = OpenSSL::PKey::RSA.new(PRIVATE_KEY)
    JWT.encode({data: "test"}, private_key, "RS512")
  end
  let(:invalid_token) { "invalid.token.here" }
  let(:target_url) { "https://jsonplaceholder.typicode.com/posts" }

  # Mock external requests with WebMock or a similar tool (if desired)

  before(:each) do
    stub_request(:get, "https://jsonplaceholder.typicode.com/posts")
      .with(headers: {"x-foo": "bar"})
      .to_return(status: 200, body: "", headers: {})
    stub_request(:put, "https://jsonplaceholder.typicode.com/posts/1")
      .to_return(status: 200, body: {title: "updated title"}.to_json, headers: {})
    stub_request(:post, "https://jsonplaceholder.typicode.com/posts")
      .to_return(status: 201, body: {title: "foo", body: "bar", userId: 1}.to_json, headers: {})
  end

  context "preflight request" do
    before(:each) do
      options "/?url=#{target_url}"
    end

    it "returns CORS headers" do
      expect_header("access-control-allow-origin", "*")
    end
  end

  context "when x-bump-jwt-token is present" do
    context "and is valid" do
      before(:each) do
        header "x-bump-jwt-token", valid_token
        header "x-foo", "bar"
        get "/?url=#{target_url}"
      end

      it "returns 200" do
        expect(last_response.status).to eq(200)
      end

      it "returns cors headers" do
        expect_header("access-control-allow-origin", "*")
      end
    end

    it "returns 401 for an invalid token" do
      header "x-bump-jwt-token", invalid_token
      get "/?url=#{target_url}"

      expect(last_response.status).to eq(401)
      expect_header("access-control-allow-origin", "*")
      expect(JSON.parse(last_response.body)["error"]).to eq("Invalid token")
    end
  end

  context "when x-bump-jwt-token is missing" do
    it "returns 401 Unauthorized" do
      get "/?url=#{target_url}"

      expect(last_response.status).to eq(401)
      expect_header("access-control-allow-origin", "*")
      expect(JSON.parse(last_response.body)["error"]).to eq("x-bump-jwt-token header is missing")
    end
  end

  context "request forwarding" do
    it "forwards headers and body for POST requests" do
      header "x-bump-jwt-token", valid_token
      header "Content-Type", "application/json"
      post "/?url=#{target_url}", {title: "foo", body: "bar", userId: 1}.to_json

      expect(last_response.status).to eq(201)  # Expect created status if target server responds as expected
      response_body = JSON.parse(last_response.body)
      expect_header("access-control-allow-origin", "*")
      expect(response_body["title"]).to eq("foo")
      expect(response_body["body"]).to eq("bar")
      expect(response_body["userId"]).to eq(1)
    end

    it "forwards headers and body for PUT requests" do
      header "x-bump-jwt-token", valid_token
      header "Content-Type", "application/json"
      put "/?url=#{target_url}/1", {id: 1, title: "updated title"}.to_json

      expect(last_response.status).to eq(200)  # Expect OK status if target server responds as expected
      response_body = JSON.parse(last_response.body)
      expect(response_body["title"]).to eq("updated title")
    end
  end
end
