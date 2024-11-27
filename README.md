# Proxy Server with JWT Authentication

This is a lightweight HTTP proxy server built using the Sinatra framework. It acts as a pass-through proxy, allowing requests to be forwarded to a specified target URL. Additionally, it provides a JWT (JSON Web Token) verification mechanism to allow only specific requests.

## Features

- **CORS Support**: Handles CORS headers, allowing cross-origin requests.
- **JWT verification**: Verifies the presence and validity of the `x-cors-toujours-token` header to ensure requests are allowed.
- **Flexible HTTP Method Support**: Supports `GET`, `POST`, `PUT`, `PATCH`, and `DELETE` methods for forwarding client requests to the target server.
- **Automatic Request Forwarding**: Forwards requests to the specified target URL while preserving headers and request bodies.
- **Path Parameter Support**: Supports dynamic path parameters in URL patterns (e.g., `/posts/{post_id}/comments/{id}`).

## Getting Started

### Prerequisites

- Ruby (>= 3.0)
- Bundler

Install the required gems:
```bash
bundle install
```

### Configuration

The proxy is configured via environment variables. In local or test environment you can set those variables thanks to a `.env` file.

#### JWT signing keys

Use the following script to create your first JWT signing keys:
```bash
./rotate_keys.rb
```

This will generate a RSA key pair and add it to the `.env` file with the following variables:
- `JWT_SIGNING_PUBLIC_KEY`: Public key for token verification (used by the proxy)
- `JWT_SIGNING_PRIVATE_KEY`: Private key for token signing (used by clients making the requests)

If later on you need to rotate the keys you will need to remove them manually from the .env file before exectuting the script again.

#### `x-cors-toujours-token` header

By default, the proxy will read the verification token from the header `x-cors-toujours-token`. You can change the name of the header by adding the following environment variable to your `.env` file:

- `CORS_TOUJOURS_TOKEN_HEADER="x-my-custom-header-name"`

### Starting the Server Locally

Run the following command to start the server on port 4567:
```bash
bundle exec puma
```

### Run the Tests

Run the following command to run the test suite:
```bash
bundle exec rspec --color -fd spec
```

## Usage

### Authentication

The server verifies the `x-cors-toujours-token` header for every request (name of the header is customizable - see [configuration details](#configuration)). The JWT token must contain the following claims:

- `servers`: Array of allowed target server URLs
- `verb`: Allowed HTTP method for the request to be made (GET, POST, PUT, PATCH, or DELETE)
- `path`: Allowed path pattern, supporting path parameters (e.g., `/posts/{post_id}`)
- `exp`: Token expiration timestamp

E.g.: A client sending a request to `POST https://bump.sh/api/v1/ping`
via the proxy will need to include an encoded JWT token in
the `x-cors-toujours-token` header, whose decoded value would look like:
```json
{
  "servers": ["https://bump.sh"],
  "path": "/api/v1/ping",
  "verb": "POST",
  "exp": "2025-01-01T00:00:00Z"
}
```

If the token is missing, invalid, or doesn't meet those requirements,
the request will be rejected with a `403 Forbidden` HTTP error.

### Path Parameters

The server supports dynamic path parameters in URL patterns. For example:
- Pattern: `/posts/{post_id}/comments/{id}`
- Valid URL: `/posts/123/comments/456`

### Example Requests

**GET request:**
```bash
curl -X GET "http://localhost:4567/https://jsonplaceholder.typicode.com/todos" \
     -H "x-cors-toujours-token: YOUR_JWT_TOKEN"
```

**PATCH request:**
```bash
curl -X PATCH "http://localhost:4567/https://jsonplaceholder.typicode.com/posts/1" \
     -H "Content-Type: application/json" \
     -H "x-cors-toujours-token: YOUR_JWT_TOKEN" \
     -d '{"title":"foo"}'
```

### CORS Support

The server includes the following CORS headers for cross-origin access:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: OPTIONS, GET, POST, PUT, PATCH, DELETE`
- `Access-Control-Allow-Headers: Content-Type, Authorization, x-cors-toujours-token, x-requested-with`

Preflight OPTIONS requests are handled automatically.

## Error Handling

The server returns different status codes based on various error conditions:

- **401 Unauthorized**:
  - Missing `x-cors-toujours-token` header
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

This project is licensed under the AGPL License.

## Contributing

Feel free to open issues and submit pull requests!
