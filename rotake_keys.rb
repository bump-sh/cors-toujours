#!/usr/bin/env ruby
require 'openssl'
require 'debug'

# Define the RSA key size
key_size = 2048

# Generate a new RSA key pair
rsa_key = OpenSSL::PKey::RSA.new(key_size)

# Display the private key in PEM format
puts "Private Key:"
private_key = rsa_key.to_pem
puts private_key
`sed -i '' '/JWT_SIGNING_PRIVATE_KEY/d'  ./.env`
`echo 'JWT_SIGNING_PRIVATE_KEY="#{private_key}"' >> ./.env`

# Display the public key in PEM format
puts "\nPublic Key:"
public_key =  rsa_key.public_key.to_pem
puts public_key
`sed -i '' '/JWT_SIGNING_PUBLIC_KEY/d'  ./.env`
`echo 'JWT_SIGNING_PUBLIC_KEY="#{public_key}"' >> ./.env`

