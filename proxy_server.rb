require "sinatra/base"
require "net/http"
require "uri"
require "json"
require "jwt"
require "openssl/pkey"

if ["development", "test"].include? ENV['RACK_ENV']
  require "dotenv/load"
  require "debug"
end

class ProxyServer < Sinatra::Base
  set :port, 4567
  # set :logging, true

  # Secret key for JWT verification
  PUBLIC_KEY = ENV.fetch("JWT_SIGNING_PUBLIC_KEY").gsub("\\n", "\n")

  error JWT::ExpiredSignature do
    halt 401, {error: "Token has expired"}.to_json
  end

  error JWT::DecodeError do
    halt 401, {error: "Invalid token"}.to_json
  end

  error JWT::MissingRequiredClaim do |error|
    halt 401, {error: "Token has #{error.to_s.downcase}"}.to_json
  end

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
        # JWT.decode returns [payload, headers]
        @payload, _ = JWT.decode(
          token,
          public_key,
          true, # Verify signature
          {
            required_claims: ["exp", "verb", "path", "servers"],
            algorithm: "RS512"
          }
        )

        # Verify HTTP method matches
        unless @payload["verb"] == request.request_method
          halt 403, {error: "HTTP method not allowed"}.to_json
        end

        # Get target URL from the request
        target_url = request.fullpath[1..].gsub(":/", "://")
        uri = URI.parse(target_url)

        # Verify server is allowed
        # base_url = "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? '' : ":#{uri.port}"}"
        matching_server = @payload["servers"].find { |server| target_url.to_s.include?(server) }

        unless matching_server
          halt 403, {error: "Server not allowed"}.to_json
        end

        # Verify path matches the pattern
        unless path_matches_pattern?(uri.path, @payload["path"])
          halt 403, {error: "Path not allowed"}.to_json
        end
      end
    end
  end

  # OPTIONS request for preflight
  options "*" do
    200
  end

  helpers do
    def path_matches_pattern?(actual_path, pattern_path)
      # Convert pattern with {param} to regex
      # e.g., "/docs/{doc_id}/branches/{slug}" becomes /^\/docs\/[^\/]+\/branches\/[^\/]+$/
      pattern_regex = pattern_path.gsub(/\{[^}]+\}/, '[^/]+')
      pattern_regex = "^#{pattern_regex}$"

      # Match the actual path against the regex
      Regexp.new(pattern_regex).match?(actual_path)
    end

    def forward_request(method)
      target_url = request.fullpath[1..].gsub(":/", "://")
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

      # Override host
      target_request["host"] = uri.hostname

      # Log the headers for debugging purposes
      # puts "Forwarding headers to target request:"
      # target_request.each_header do |header, value|
      #   puts "#{header}: #{value}"
      # end

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
