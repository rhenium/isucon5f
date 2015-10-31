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
require "digest/sha2"

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

    def redis
      Thread.current[:redis] ||= Redis.new
    end

    def authenticate(email, password)
      if preu = redis.hget("users", email)
        preuu = Oj.load(preu)
        if preuu[:passhash] == Digest::SHA512.digest(preuu[:salt] + password)
          session[:user] = preu
          @user = preuu
        end
      end
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
    nid = redis.incr("user_lid")
    salt = generate_salt
    passhash = Digest::SHA512.digest(salt + params['password'])
    u = { id: nid.to_i, email: params['email'], grade: params['grade'], passhash: hash, salt: salt }
    redis.hset("users", email, Oj.dump(u))
    redis.hset("subscriptions", nid.to_s, "{}")
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

    redis.hset("subscriptions", user[:id].to_s, Oj.dump(arg))
    redirect '/modify'
  end

  def fetch_api(uri, headers, params)
    @client ||= HTTPClient.new
    if uri.start_with? "https://"
      @client.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    res = @client.get_content(uri, params, headers)
  end

  def api_req(service, conf)
    data = case service
    when "ken", "ken2"
      if service == "ken"
        c = conf["keys"].first
      else
        c = conf["params"]["zipcode"]
      end
      a = redis.hget("ken", c)
      unless a
        a = fetch_api("http://api.five-final.isucon.net:8080/#{c}", {}, {})
        redis.hset("ken", c, a)
      end
      Oj.load(a)
    when "surname", "givenname"
      c = conf["params"]["q"]
      a = redis.hget(service, c)
      unless a
        a = fetch_api("http://api.five-final.isucon.net:8081/#{service}", {}, conf["params"])
        redis.hset(service, c, a)
      end
      Oj.load(a)
    when "perfectsec_attacked"
      c = conf["token"]
      _a = redis.hget(service, c)
      a = Oj.load(_a) if _a
      if !_a || Time.at(a["updated_at"]) < Time.now - 33 # TODO
        _a = fetch_api("https://api.five-final.isucon.net:8443/attacked_list", {"X-PERFECT-SECURITY-TOKEN" => c}, {})
        redis.hset(service, c, _a)
        a = Oj.load(_a)
      end
      a
    when "tenki"
      c = conf["token"]
      _a = redis.get("tenki")
      a = Oj.load(_a) if _a
      if !_a
        _a = fetch_api("http://api.five-final.isucon.net:8988/", {}, {"zipcode" => c})
        redis.setex("tenki", 3, _a) # set TTL 3 secs
        a = Oj.load(_a)
      end
      a
    else
      method, token_type, token_key, uri_template = $endpoints[service]
      headers = {}
      params = (conf['params'] && conf['params'].dup) || {}
      case token_type
      when 'header' then headers[token_key] = conf['token']
      when 'param' then params[token_key] = conf['token']
      end
      uri = sprintf(uri_template, *conf['keys'])
      Oj.load fetch_api(uri, headers, params)
    end
    {"service" => service, "data" => data}
  end

  get '/data' do
    unless user = current_user
      halt 403
    end

    arg_json = redis.hget("subscriptions", user[:id].to_s)
    arg = Oj.load(arg_json)

    data = []

    arg.each_pair do |service, conf|
      data << api_req(service, conf)
    end

    json data
  end

  get '/initialize' do
    file = File.expand_path("../../sql/initialize.sql", __FILE__)
    system("psql", "-f", file, "isucon5f")
    $init[]
  end
end
