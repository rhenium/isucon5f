require_relative './app.rb'
require 'pg'

$config = {
  db: {
    host: ENV['ISUCON5_DB_HOST'] || 'localhost',
    port: ENV['ISUCON5_DB_PORT'] && ENV['ISUCON5_DB_PORT'].to_i,
    username: ENV['ISUCON5_DB_USER'] || 'isucon',
    password: ENV['ISUCON5_DB_PASSWORD'],
    database: ENV['ISUCON5_DB_NAME'] || 'isucon5f',
  },
}

$init = -> {
  file = File.expand_path("../../sql/initialize.sql", __FILE__)
  system("psql", "-f", file, "isucon5f")

  conn = PG.connect(
    host: $config[:db][:host],
    port: $config[:db][:port],
    user: $config[:db][:username],
    password: $config[:db][:password],
    dbname: $config[:db][:database],
    connect_timeout: 3600
  )

  $endpoints = {}
  conn.exec_params("select * from endpoints") { |result|
    result.each { |tuple|
      $endpoints[tuple['service']] = [tuple["meth"], tuple["token_type"], tuple["token_key"], tuple["uri"]]
    }
  }

  redis = Redis.new(host: ENV["REDIS_IP"])
  redis.del("subscriptions")
  conn.exec_params("select * from subscriptions") { |result|
    result.each.each_slice(100) { |ts|
      a = []
      ts.each { |t|
        a << t['user_id'] << t["arg"]
      }
      redis.hmset("subscriptions", *a)
    }
  }

  lid = 0
  redis.del("users")
  conn.exec_params("select * from users") { |result|
    result.each.each_slice(100) { |ts|
      a = []
      ts.each { |tuple|
        lid = tuple['id'].to_i
        a << tuple["email"] << Oj.dump({id: tuple['id'].to_i, email: tuple['email'], grade: tuple['grade'], passhash: tuple['passhash'], salt: tuple['salt']})
      }
      redis.hmset("users", *a)
    }
  }

  redis.set("user_lid", lid)
}

$init[]

use Rack::Lineprof
run Isucon5f::WebApp
