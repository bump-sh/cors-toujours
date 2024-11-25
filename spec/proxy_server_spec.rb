ENV["RACK_ENV"] ||= "test"

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

  def expect_json_body(k, v)
    expect(JSON.parse(last_response.body)[k]).to eq v
  end

  let(:verb) { "GET" }
  let(:servers) do
    [
      "https://jsonplaceholder.typicode.com/"
    ]
  end

  let(:path) { "/posts" }
  let(:exp) { Time.now.to_i + 4 * 3600 }

  let(:payload) do
    {
      servers: servers,
      verb: verb,
      path: path,
      exp: exp
    }
  end

  let(:proxy_token) do
    private_key = OpenSSL::PKey::RSA.new(PRIVATE_KEY)
    JWT.encode(payload, private_key, "RS512")
  end

  let(:invalid_proxy_token) { "invalid.token.here" }

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
    ["https://staging.bump.sh/api/v1/ping", "https://bump.sh/api/Custom+Api/v1/ping"].each do |server|
      stub_request(:get, server)
        .with(headers: {
            'Accept' => '*/*',
            'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
            'Cookie'=>'',
            'Host'=> URI.parse(server).host,
            'User-Agent'=>'Ruby',
            'X-Foo'=>'bar'
          })
        .to_return(status: 200, body: "", headers: {})
    end
  end

  context "preflight request" do
    before(:each) do
      options "/#{target_url}"
    end

    it "returns CORS headers" do
      expect_header("access-control-allow-origin", "*")
    end
  end

  context "when x-bump-jwt-token is present" do
    context "and is valid" do
      context "when no path params" do
        before(:each) do
          header "x-bump-proxy-token", proxy_token
          header "x-foo", "bar"
          get "/#{target_url}"
        end

        it "returns 200" do
          expect(last_response.status).to eq(200)
        end

        context "when server contains some path like /api/v1" do
          let(:payload) do
            {
              "servers": [
                "https://staging.bump.sh/api/v1",
                "http://localhost:3000/api/v1",
                "https://bump.sh/api/v1"
              ],
              "verb": "GET",
              "path": "/ping",
              "exp": Time.now.to_i + 500
            }
          end

          let(:target_url) { "https://staging.bump.sh/api/v1/ping"}

          it "returns 200" do
            expect(last_response.status).to eq(200)
          end

          context "when server contains path with regexp character" do
            let(:payload) do
              {
                "servers": [
                  "https://bump.sh/api/Custom+Api/v1"
                ],
                "verb": "GET",
                "path": "/ping",
                "exp": Time.now.to_i + 500
              }
            end

            let(:target_url) { "https://bump.sh/api/Custom+Api/v1/ping"}

            it "returns 200" do
              expect(last_response.status).to eq(200)
            end
          end
        end

        it "returns cors headers" do
          expect_header("access-control-allow-origin", "*")
        end
      end

      context "when multiple path params" do
        let(:path) { "/posts/{post_id}/comments/{id}" }
        let(:target_url) { "https://jsonplaceholder.typicode.com/posts/123/comments/456" }

        before(:each) do
          stub_request(:get, "https://jsonplaceholder.typicode.com/posts/123/comments/456")
            .with(
              headers: {
              'Accept'=>'*/*',
              'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
              'Cookie'=>'',
              'Host'=>'jsonplaceholder.typicode.com',
              'User-Agent'=>'Ruby',
              'X-Foo'=>'bar'
              })
            .to_return(status: 200, body: "", headers: {})

          header "x-bump-proxy-token", proxy_token
          header "x-foo", "bar"
          get "/#{target_url}"


        end

        it "returns 200" do
          expect(last_response.status).to eq(200)
        end

        it "returns cors headers" do
          expect_header("access-control-allow-origin", "*")
        end
      end


    end

    context "but is invalid" do
      before(:each) do
          header "x-bump-proxy-token", invalid_proxy_token
          get "/#{target_url}"
        end

      it "returns a 401 Unauthorized status" do
        expect(last_response.status).to eq(401)
      end

      it "includes CORS headers in the response" do
        expect_header("access-control-allow-origin", "*")
      end

      it "returns the correct error message in the response body" do
        expect(JSON.parse(last_response.body)["error"]).to eq("Invalid token")
      end
    end

    describe  "Token Payload" do
      context "when token is expired" do
        let(:exp) { Time.now.to_i - 500 } # 5 minutes ago

        before(:each) do
          header "x-bump-proxy-token", proxy_token
          header "x-foo", "bar"
          get "/#{target_url}"
        end

        it "returns 401" do
          expect(last_response.status).to eq(401)
        end

        it "has error message" do
          expect_json_body("error", "Token has expired")
        end

        it "returns cors headers" do
          expect_header("access-control-allow-origin", "*")
        end
      end

      context "when token has a missing claim" do
        let(:payload) do
          {}
        end

        before(:each) do
          header "x-bump-proxy-token", proxy_token
          header "x-foo", "bar"
          get "/#{target_url}"
        end

        it "returns 401" do
          expect(last_response.status).to eq(401)
        end

        it "has error message" do
          expect_json_body("error", "Token has missing required claim exp")
        end

        it "returns cors headers" do
          expect_header("access-control-allow-origin", "*")
        end
      end

      context "when HTTP method is not allowed" do
        let(:verb) { "PATCH" } # wrong http method

        before(:each) do
          header "x-bump-proxy-token", proxy_token
          header "x-foo", "bar"
          get "/#{target_url}"
        end

        it "returns 403" do
          expect(last_response.status).to eq(403)
        end

        it "has error message" do
          expect_json_body("error", "HTTP method not allowed")
        end

        it "returns cors headers" do
          expect_header("access-control-allow-origin", "*")
        end
      end

      context "when server is not allowed" do
        let(:servers) { ["https://staging.bump.sh/api/v1/"] }

        before(:each) do
          header "x-bump-proxy-token", proxy_token
          header "x-foo", "bar"
          get "/#{target_url}"
        end

        it "returns 403" do
          expect(last_response.status).to eq(403)
        end

        it "has error message" do
          expect_json_body("error", "Server not allowed")
        end

        it "returns cors headers" do
          expect_header("access-control-allow-origin", "*")
        end
      end

      context "when is not allowed" do
        let(:path) { "/comments" }

        before(:each) do
          header "x-bump-proxy-token", proxy_token
          header "x-foo", "bar"
          get "/#{target_url}"
        end

        it "returns 403" do
          expect(last_response.status).to eq(403)
        end

        it "has error message" do
          expect_json_body("error", "Path not allowed")
        end

        it "returns cors headers" do
          expect_header("access-control-allow-origin", "*")
        end
      end
    end
  end

  context "when x-bump-proxy-token is missing" do
    before(:each) do
        get "/#{target_url}"
      end

    it "returns 401 Unauthorized status" do
      expect(last_response.status).to eq(401)
    end

    it "includes CORS headers in the response" do
      expect_header("access-control-allow-origin", "*")
    end

    it "returns the correct error message in the response body" do
      expect(JSON.parse(last_response.body)["error"]).to eq("x-bump-proxy-token header is missing")
    end
  end

  context "request forwarding" do
    context "when POST requests" do
      let(:verb) { "POST" }
      let(:request_body) { {title: "foo", body: "bar", userId: 1} }

      before(:each) do
        header "x-bump-proxy-token", proxy_token
        header "Content-Type", "application/json"
        post "/#{target_url}", request_body.to_json
      end

      it "returns a 201 Created status" do
        expect(last_response.status).to eq(201)
      end

      it "includes CORS headers in the response" do
        expect_header("access-control-allow-origin", "*")
      end

      it "returns the correct title in the response body" do
        response_body = JSON.parse(last_response.body)
        expect(response_body["title"]).to eq("foo")
      end

      it "returns the correct body in the response body" do
        response_body = JSON.parse(last_response.body)
        expect(response_body["body"]).to eq("bar")
      end

      it "returns the correct userId in the response body" do
        response_body = JSON.parse(last_response.body)
        expect(response_body["userId"]).to eq(1)
      end
    end

    context "when PUT requests" do
      let(:verb) { "PUT" }
      let(:path) { "/posts/{id}" }

      before(:each) do
        header "x-bump-proxy-token", proxy_token
        header "Content-Type", "application/json"
        put "/#{target_url}/1", {id: 1, title: "updated title"}.to_json
      end

      it "forwards headers and body for PUT requests" do
        expect(last_response.status).to eq(200)  # Expect OK status if target server responds as expected
        response_body = JSON.parse(last_response.body)
        expect(response_body["title"]).to eq("updated title")
      end
    end
  end
end
