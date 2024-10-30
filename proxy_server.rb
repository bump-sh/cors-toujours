require "sinatra/base"
require "net/http"
require "uri"
require "json"
require "jwt"
require "debug"
require "dotenv/load"
require "openssl/pkey"

class ProxyServer < Sinatra::Base
  set :port, 4567
  # set :logging, true

  # Secret key for JWT verification
  PUBLIC_KEY = ENV.fetch("JWT_SIGNING_PUBLIC_KEY").gsub("\\n", "\n")

  # Handle CORS headers
  before do
    headers "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => ["OPTIONS", "GET", "POST", "PUT", "PATCH", "DELETE"],
      "Access-Control-Allow-Headers" => "Content-Type, Authorization, x-bump-proxy-token, x-requested-with"
  end

  # Verify JWT token presence and signature
  before do
    if request.env["REQUEST_METHOD"] != "OPTIONS"
      token = request.env["HTTP_X_BUMP_PROXY_TOKEN"]

      # Check if token is missing
      if token.nil?
        headers "Content-Type" => "application/json"
        halt 401, {error: "x-bump-proxy-token header is missing"}.to_json
      end

      # Verify JWT token
      begin
        public_key = OpenSSL::PKey.read(PUBLIC_KEY)
        JWT.decode(token, public_key, true, {algorithm: "RS512"})
      rescue JWT::DecodeError
        halt 401, {error: "Invalid token"}.to_json
      end
    end
  end

  # OPTIONS request for preflight
  options "*" do
    200
  end

  helpers do
    def forward_request(method)
      target_url = params["splat"][0].gsub(":/", "://")
      uri = URI.parse(target_url)

      # Set up the request to the target server
      target_request =
        case method
        when "GET" then Net::HTTP::Get.new(uri)
        when "POST" then Net::HTTP::Post.new(uri)
        when "PUT" then Net::HTTP::Put.new(uri)
        when "PATCH" then Net::HTTP::Patch.new(uri)
        when "DELETE" then Net::HTTP::Delete.new(uri)
        end

      # Transfer relevant headers from the client to the target request
      client_headers = request.env.select { |key, _| key.start_with?("HTTP_") }
      client_headers.each do |header, value|
        formatted_header = header.sub("HTTP_", "").split("_").map(&:capitalize).join("-")
        target_request[formatted_header] = value unless formatted_header == "X-Bump-Proxy-Token"
      end

      # Forward request body for POST, PUT and PATCH methods
      if !%w[GET HEAD OPTIONS].include?(method) && request.body && request.content_type
        target_request.content_type = request.content_type
        target_request.body = request.body.read
      end

      # Log the headers for debugging purposes
      puts "Forwarding headers to target request:"
      target_request.each_header do |header, value|
        puts "#{header}: #{value}"
      end
      # Execute the request to the target server
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        response = http.request(target_request)

        # Pass the target server response back to the client
        status response.code
        headers "Content-Type" => response.content_type

        content_encoding = response.get_fields "content-encoding"
        if content_encoding && content_encoding.include?("gzip")
          body Zlib::GzipReader.new(StringIO.new(response.body)).read
        else
          body response.body
        end
      end
    end
  end

  # Proxy endpoints
  get "/*" do
    forward_request("GET")
  end

  post "/*" do
    forward_request("POST")
  end

  put "/*" do
    forward_request("PUT")
  end

  patch "/*" do
    forward_request("PATCH")
  end

  delete "/*" do
    forward_request("DELETE")
  end
end
