require_relative './app.rb'

$config = {
  db: {
    host: ENV['ISUCON5_DB_HOST'] || 'localhost',
    port: ENV['ISUCON5_DB_PORT'] && ENV['ISUCON5_DB_PORT'].to_i,
    username: ENV['ISUCON5_DB_USER'] || 'isucon',
    password: ENV['ISUCON5_DB_PASSWORD'],
    database: ENV['ISUCON5_DB_NAME'] || 'isucon5f',
  },
}

init = -> {
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

  redis = Redis.new
  redis.flushdb
  conn.exec_params("select * from subscriptions") { |result|
    result.each.each_slice(100) { |ts|
      a = []
      ts.each { |t|
        a << t['user_id'] << t["arg"]
      }
      redis.hmset("subscriptions", *a)
    }
  }
}

init[]

use Rack::Lineprof
run Isucon5f::WebApp
