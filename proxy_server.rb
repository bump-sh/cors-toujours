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
  PUBLIC_KEY = OpenSSL::PKey.read(
    ENV.fetch("JWT_SIGNING_PUBLIC_KEY").gsub("\\n", "\n")
  ).freeze

  # Remove some headers from proxied requests.
  HEADERS_SKIP_FORWARD = [
    "set-cookie", # Don't forward authenticated cookies data
    "transfer-encoding" # Don't forward transfer-encoding as this is a
                        # “hop-by-hop” header which needs to be
                        # consumed by the proxy when reading the
                        # target response.
  ].freeze

  TOKEN_HEADER = ENV.fetch(
    "CORS_TOUJOURS_TOKEN_HEADER_NAME",
    "x-cors-toujours-token"
  ).split("_").join("-").downcase.freeze

  error JWT::ExpiredSignature do
    headers "Content-Type" => "application/json"
    halt 401, {error: "Token has expired"}.to_json
  end

  error JWT::DecodeError do
    headers "Content-Type" => "application/json"
    halt 401, {error: "Invalid token"}.to_json
  end

  error JWT::MissingRequiredClaim do |error|
    headers "Content-Type" => "application/json"
    halt 401, {error: "Token has #{error.to_s.downcase}"}.to_json
  end

  error do |error|
    headers "Content-Type" => "application/json"
    halt 502, {error: error.message}.to_json
  end

  # Handle CORS headers
  before do
    headers "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => ["OPTIONS", "GET", "POST", "PUT", "PATCH", "DELETE"],
      "Access-Control-Allow-Headers" => "Content-Type, Authorization, #{::ProxyServer::TOKEN_HEADER}, x-requested-with"
  end

  # Verify JWT token presence and signature
  before do
    if request.env["REQUEST_METHOD"] != "OPTIONS"
      token_header = ::ProxyServer::TOKEN_HEADER.split("-").join("_").upcase
      token = request.get_header("HTTP_#{token_header}")

      # Check if token is missing
      if token.nil?
        headers "Content-Type" => "application/json"
        halt 401, {error: "#{::ProxyServer::TOKEN_HEADER} header is missing"}.to_json
      end

      # Verify JWT token
      begin
        # JWT.decode returns [payload, headers]
        @payload, _ = JWT.decode(
          token,
          ::ProxyServer::PUBLIC_KEY,
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
        target_url = request.path[1..].gsub(":/", "://")

        # Verify server is allowed
        matching_server = @payload["servers"].find { |server| target_url.to_s.start_with?(server) }&.chomp("/")

        unless matching_server
          halt 403, {error: "Server not allowed"}.to_json
        end

        # Verify path matches the pattern
        unless path_matches_pattern?(path_from_target_url(target_url, matching_server), @payload["path"])
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
    def path_from_target_url(target_url, matching_server)
      target_url.gsub(/^#{Regexp.escape(matching_server)}/, "")
    end

    def path_matches_pattern?(actual_path, pattern_path)
      # Convert pattern with {param} to regex
      # e.g., "/docs/{doc_id}/branches/{slug}" becomes /^\/docs\/[^\/]+\/branches\/[^\/]+$/
      pattern_regex = pattern_path.gsub(/\{[^}]+\}/, '[^/]+')
      pattern_regex = "^#{pattern_regex}$"

      # Match the actual path against the regex
      Regexp.new(pattern_regex).match?(actual_path)
    end

    def skip_header?(key)
      HEADERS_SKIP_FORWARD.any? do |header|
        key.downcase.start_with?(header)
      end
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
      request.each_header do |header, value|
        formatted_header = header.sub("HTTP_", "").split("_").map(&:capitalize).join("-")

        next unless header.start_with?("HTTP_")
        next if formatted_header.downcase == ::ProxyServer::TOKEN_HEADER

        target_request[formatted_header] = value
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
        # This has the effect to .read the response body directly. In
        # case we want to stream the response we might want to use a
        # block with http.request(..) do |response| at some
        # point. Especially when we will want to proxy file download
        # requests.
        response = http.request(target_request)

        # Forward the raw target response back to the client.

        # RESPONSE CODE
        status response.code

        forwarded_headers = {}
        response.each_header do |key, value|
          next if skip_header?(key)

          forwarded_headers[key] = value
        end
        # RESPONSE HEADERS
        headers forwarded_headers

        # RESPONSE BODY
        body response.body
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
