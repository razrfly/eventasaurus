import Config

# Configure the database
config :eventasaurus, EventasaurusApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eventasaurus_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
