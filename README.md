# Proxy Server with JWT Authentication

This is a lightweight HTTP proxy server built using the Sinatra framework. It acts as a pass-through proxy, allowing requests to be forwarded to a specified target URL. Additionally, it provides JWT (JSON Web Token) authentication to secure requests.

## Features

- **CORS Support**: Handles CORS headers, allowing cross-origin requests.
- **JWT Authentication**: Verifies the presence and validity of the `x-bump-jwt-token` header to ensure requests are authorized.
- **Flexible HTTP Method Support**: Supports `GET`, `POST`, `PUT`,`PATCH`, and `DELETE` methods for forwarding client requests to the target server.
- **Automatic Request Forwarding**: Forwards requests to the specified target URL while preserving headers and request bodies.

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

- Set the `SECRET_KEY` environment variable for JWT verification:
  ```ruby
  # .env
  SECRET_KEY = 'your-secret-key'
  ```

### Starting the Server

Run the following command to start the server on port 4567:
```bash
ruby proxy_server.rb
```

### Making Requests

- Include the `x-bump-jwt-token` header with a valid JWT in your requests.
- Ensure the target URL is provided as a query parameter (e.g., `/proxy?url=https://example.com`).

## Usage

### Authentication

The server verifies the `x-bump-jwt-token` for every request. If the token is missing or invalid, it returns a `401 Unauthorized` error.

### Proxy Endpoints

The server provides the following endpoints for request forwarding:

- **GET** `?url=your-target-url`
- **POST** `?url=your-target-url`
- **PUT** `?url=your-target-url`
- **PATCH** `?url=your-target-url`
- **DELETE** `?url=your-target-url`

Each endpoint forwards the request to the target URL specified in the query parameter.

### Example Requests

**GET request:**
```bash
curl -X GET "http://localhost:4567/?url=https://jsonplaceholder.typicode.com/posts" -H "x-bump-jwt-token: YOUR_TOKEN"
```

**POST request:**
```bash
curl -X POST "http://localhost:4567/?url=https://jsonplaceholder.typicode.com/posts" \
     -H "Content-Type: application/json" \
     -H "x-bump-jwt-token: YOUR_TOKEN" \
     -d '{"title":"foo","body":"bar","userId":1}'
```

### CORS Support

The server includes CORS headers for cross-origin access. Preflight OPTIONS requests are handled by default.

## Error Handling

- **401 Unauthorized**: Returned if the `x-bump-jwt-token` header is missing or if the token is invalid.
- **502 Bad Gateway**: Returned if there is an issue with the target server.

## License

This project is licensed under the MIT License.

## Contributing

Feel free to open issues and submit pull requests!
