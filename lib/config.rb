$:.unshift File.expand_path(File.dirname(__FILE__))

env    = ENV['RACK_ENV'] || "development"

if env == 'development'
  require 'sqlite3'
  require 'yaml'
  @@config = YAML.load_file('database.yml')[env]
else
  require 'pg'
  require 'uri'
  db = URI.parse(ENV['HEROKU_POSTGRESQL_GOLD'])

  @@config = {
    "adapter" => db.scheme == 'postgres' ? 'postgresql' : db.scheme,
    "host" => db.host,
    "username" => db.user,
    "password" => db.password,
    "database" => db.path[1..-1],
    "encoding" => 'utf8'
  }
end
