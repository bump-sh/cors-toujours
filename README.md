# Proxy Server with JWT Authentication

This is a lightweight HTTP proxy server built using the Sinatra framework. It acts as a pass-through proxy, allowing requests to be forwarded to a specified target URL. Additionally, it provides JWT (JSON Web Token) authentication to secure requests.

## Features

- **CORS Support**: Handles CORS headers, allowing cross-origin requests.
- **JWT Authentication**: Verifies the presence and validity of the `x-bump-proxy-token` header to ensure requests are authorized.
- **Flexible HTTP Method Support**: Supports `GET`, `POST`, `PUT`, `PATCH`, and `DELETE` methods for forwarding client requests to the target server.
- **Automatic Request Forwarding**: Forwards requests to the specified target URL while preserving headers and request bodies.
- **Path Parameter Support**: Supports dynamic path parameters in URL patterns (e.g., `/posts/{post_id}/comments/{id}`).

## Getting Started

### Prerequisites

- Ruby (>= 2.7)
- Sinatra gem (`sinatra`)
- JWT gem (`jwt`)

Install the required gems:
```bash
gem install sinatra jwt
```

### Configuration

Use the script to rotate the JWT signing keys:
```bash
./rotate_keys.rb
```
This will generate new RSA key pairs and add them to the `.env` file with the following variables:
- `JWT_SIGNING_PUBLIC_KEY`: Public key for token verification
- `JWT_SIGNING_PRIVATE_KEY`: Private key for token signing

### Starting the Server

Run the following command to start the server on port 4567:
```bash
rackup config.ru
```

### Run the Tests

Run the following command to run the test suite:
```bash
RACK_ENV=test bundle exec rspec --color -fd spec/proxy_server_spec.rb
```

## Usage

### Authentication

The server verifies the `x-bump-proxy-token` header for every request. The JWT token must contain the following claims:

- `servers`: Array of allowed target server URLs
- `verb`: Allowed HTTP method for the request (GET, POST, PUT, PATCH, or DELETE)
- `path`: Allowed path pattern, supporting path parameters (e.g., `/posts/{post_id}`)
- `exp`: Token expiration timestamp

If the token is missing, invalid, or doesn't meet these requirements, the request will be rejected.

### Path Parameters

The server supports dynamic path parameters in URL patterns. For example:
- Pattern: `/posts/{post_id}/comments/{id}`
- Valid URL: `/posts/123/comments/456`

### Example Requests

**GET request:**
```bash
curl -X GET "http://localhost:4567/https://api.example.com/posts" \
     -H "x-bump-proxy-token: YOUR_JWT_TOKEN"
```

**POST request with path parameter:**
```bash
curl -X POST "http://localhost:4567/https://api.example.com/posts/123/comments" \
     -H "Content-Type: application/json" \
     -H "x-bump-proxy-token: YOUR_JWT_TOKEN" \
     -d '{"content":"This is a comment"}'
```

### CORS Support

The server includes the following CORS headers for cross-origin access:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: OPTIONS, GET, POST, PUT, PATCH, DELETE`
- `Access-Control-Allow-Headers: Content-Type, Authorization, x-bump-proxy-token, x-requested-with`

Preflight OPTIONS requests are handled automatically.

## Error Handling

The server returns different status codes based on various error conditions:

- **401 Unauthorized**:
  - Missing `x-bump-proxy-token` header
  - Invalid JWT token
  - Expired token

- **403 Forbidden**:
  - HTTP method doesn't match the token's `verb` claim
  - Target server not in the token's `servers` list
  - Request path doesn't match the token's `path` pattern

- **502 Bad Gateway**:
  - Issues communicating with the target server

Each error response includes a JSON body with an `error` field describing the specific error.

## License

This project is licensed under the MIT License.

## Contributing

Feel free to open issues and submit pull requests!
