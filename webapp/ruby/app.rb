require 'sinatra/base'
require 'sinatra/contrib'
require 'pg'
require 'tilt/erubis'
require 'erubis'
require 'oj'
require 'httpclient'
require 'openssl'
require 'rack-lineprof'
require "redis"
require "redis/connection/hiredis"
require 'typhoeus'
require 'typhoeus/adapters/faraday'

# bundle config build.pg --with-pg-config=<path to pg_config>
# bundle install

module Isucon5f
  module TimeWithoutZone
    def to_s
      strftime("%F %H:%M:%S")
    end
  end
  ::Time.prepend TimeWithoutZone
end

class Isucon5f::WebApp < Sinatra::Base
  use Rack::Session::Cookie, secret: (ENV['ISUCON5_SESSION_SECRET'] || 'tonymoris')
  set :erb, escape_html: true

  SALT_CHARS = [('a'..'z'),('A'..'Z'),('0'..'9')].map(&:to_a).reduce(&:+)

  helpers do
    def db
      return Thread.current[:isucon5_db] if Thread.current[:isucon5_db]
      conn = PG.connect(
        host: $config[:db][:host],
        port: $config[:db][:port],
        user: $config[:db][:username],
        password: $config[:db][:password],
        dbname: $config[:db][:database],
        connect_timeout: 3600
      )
      Thread.current[:isucon5_db] = conn
      conn
    end

    def client
      return Thread.current[:faraday] if Thread.current[:faraday]
      manager = Typhoeus::Hydra.new(max_concurrency: 100)
      con = Faraday.new(parallel_manager: manager, ssl: { verify: false }) do |builder|
        builder.adapter :typhoeus
      end
      Thread.current[:faraday] = con
    end

    def redis
      Thread.current[:redis] ||= Redis.new
    end

    def authenticate(email, password)
      query = <<SQL
SELECT id, email, grade FROM users WHERE email=$1 AND passhash=digest(salt || $2, 'sha512')
SQL
      user = nil
      db.exec_params(query, [email, password]) do |result|
        result.each do |tuple|
          user = {id: tuple['id'].to_i, email: tuple['email'], grade: tuple['grade']}
        end
      end
      session[:user] = Oj.dump(user)
      @user = user
    end

    def current_user
      return @user if @user
      if u = session[:user]
        @user = Oj.load(u)
      end
    end

    def generate_salt
      salt = ''
      32.times do
        salt << SALT_CHARS[rand(SALT_CHARS.size)]
      end
      salt
    end
  end

  get '/signup' do
    session.clear
    erb :signup
  end

  post '/signup' do
    email, password, grade = params['email'], params['password'], params['grade']
    salt = generate_salt
    insert_user_query = <<SQL
INSERT INTO users (email,salt,passhash,grade) VALUES ($1,$2,digest($3 || $4, 'sha512'),$5) RETURNING id
SQL
    user_id = db.exec_params(insert_user_query, [email,salt,salt,password,grade]).values.first.first
    redis.hset("subscriptions", user_id, "{}")
    redirect '/login'
  end

  post '/cancel' do
    redirect '/signup'
  end

  get '/login' do
    session.clear
    erb :login
  end

  post '/login' do
    authenticate params['email'], params['password']
    halt 403 unless current_user
    redirect '/'
  end

  get '/logout' do
    session.clear
    redirect '/login'
  end

  get '/' do
    unless current_user
      return redirect '/login'
    end
    erb :main, locals: {user: current_user}
  end

  get '/user.js' do
    halt 403 unless current_user
    erb :userjs, content_type: 'application/javascript', locals: {grade: current_user[:grade]}
  end

  get '/modify' do
    user = current_user
    halt 403 unless user
    erb :modify, locals: {user: user}
  end

  post '/modify' do
    user = current_user
    halt 403 unless user

    service = params["service"]
    token = params.has_key?("token") ? params["token"].strip : nil
    keys = params.has_key?("keys") ? params["keys"].strip.split(/\s+/) : nil
    param_name = params.has_key?("param_name") ? params["param_name"].strip : nil
    param_value = params.has_key?("param_value") ? params["param_value"].strip : nil

    arg_json = redis.hget("subscriptions", user[:id])
    arg = Oj.load(arg_json)
    arg[service] ||= {}
    arg[service]['token'] = token if token
    arg[service]['keys'] = keys if keys
    if param_name && param_value
      arg[service]['params'] ||= {}
      arg[service]['params'][param_name] = param_value
    end

    redis.hset("subscriptions", user[:id], Oj.dump(arg))
    redirect '/modify'
  end

  get '/data' do
    unless user = current_user
      halt 403
    end

    arg_json = redis.hget("subscriptions", user[:id].to_s)
    arg = Oj.load(arg_json)

    ress = []

    client.in_parallel do
      arg.each do |service, conf|
        method, token_type, token_key, uri_template = $endpoints[service]
        headers = {}
        params = (conf['params'] && conf['params'].dup) || {}
        uri = sprintf(uri_template, *conf['keys'])

        req = client.get(uri) { |req|
          req.params.merge!(params)
          req.params[token_key] = conf["token"] if token_type == "param"
          req.headers[token_key] = conf["token"] if token_type == "header"
        }
        ress << [service, req]
      end
    end

    data = ress.map { |service, req|
      {"service" => service, "data" => Oj.load(req.body)}
    }

    json data
  end

  get '/initialize' do
    file = File.expand_path("../../sql/initialize.sql", __FILE__)
    system("psql", "-f", file, "isucon5f")
    $init[]
  end
end
