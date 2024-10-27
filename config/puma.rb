# config/puma.rb

workers Integer(ENV['WEB_CONCURRENCY'] || 2) # Number of worker processes
threads_count = Integer(ENV['MAX_THREADS'] || 5) # Max threads per worker
threads threads_count, threads_count

preload_app!

# Define the rackup file
rackup      'config.ru' # Create this file next
port        ENV['PORT'] || 4567
environment ENV['RACK_ENV'] || 'development'

on_worker_boot do
  # Worker specific setup for Rails 4.1+
  # This block is called when a worker boots up.
end
