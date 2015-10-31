require 'pg'
require 'oj'
require "redis"
require "redis/connection/hiredis"

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
}

$sinit = -> {
  conn = PG.connect(
    host: $config[:db][:host],
    port: $config[:db][:port],
    user: $config[:db][:username],
    password: $config[:db][:password],
    dbname: $config[:db][:database],
    connect_timeout: 3600
  )
  redis = Redis.new
  redis.del("data")
  conn.exec_params("select * from subscriptions") { |result|
    result.each do |t|
      p arg = Oj.load(t["arg"])
      $update_data[redis, t["user_id"], arg]
    end
  }
}

$fetch_api = -> (method, uri, headers, params) {
  client = HTTPClient.new
  if uri.start_with? "https://"
    client.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
  fetcher = case method
            when 'GET' then client.method(:get_content)
            when 'POST' then client.method(:post_content)
            else
              raise "unknown method #{method}"
            end
  res = fetcher.call(uri, params, headers)
  Oj.load(res)
}

$update_data = -> (redis, user_id, arg) {
  data = []

  arg.each do |service, conf|
    method, token_type, token_key, uri_template = $endpoints[service]
    headers = {}
    params = (conf['params'] && conf['params'].dup) || {}
    case token_type
    when 'header' then headers[token_key] = conf['token']
    when 'param' then params[token_key] = conf['token']
    end
    uri = sprintf(uri_template, *conf['keys'])

    data << {"service" => service, "data" => $fetch_api[method, uri, headers, params]}
  end

  redis.hset("data", user_id, Oj.dump(data))
}

$init[]
$sinit[]
