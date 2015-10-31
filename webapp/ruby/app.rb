require 'sinatra/base'
require 'sinatra/contrib'
require 'tilt/erubis'
require 'erubis'
require 'oj'
require 'httpclient'
require 'openssl'
require 'rack-lineprof'
require "redis"
require "redis/connection/hiredis"
require "digest/sha2"

module Isucon5f
  module TimeWithoutZone
    def to_s
      strftime("%F %H:%M:%S")
    end
  end
  ::Time.prepend TimeWithoutZone
end

class Isucon5f::WebApp < Sinatra::Base
  helpers Sinatra::Cookies
  set :erb, escape_html: true
  set :cookie_options, domain: nil

  SALT_CHARS = [('a'..'z'),('A'..'Z'),('0'..'9')].map(&:to_a).reduce(&:+)

  helpers do
    def redis
      Thread.current[:redis] ||= Redis.new(ENV["REDIS_IP"])
    end

    def authenticate(email, password)
      if preu = redis.hget("users", email)
        preuu = Oj.load(preu)
        if preuu[:passhash] == '\\x' + Digest::SHA512.hexdigest(preuu[:salt] + password)
          cookies["user_id"] = preuu[:id]
          cookies["grade"] = preuu[:grade]
          cookies["email"] = email
          cookies["subscriptions"] = redis.hget("subscriptions", preuu[:id])
        end
      end
    end

    def generate_salt
      32.times.map { SALT_CHARS.sample }.join
    end
  end

  get '/signup' do
    cookies.delete("user_id")
    erb :signup
  end

  post '/signup' do
    nid = redis.incr("user_lid")
    salt = generate_salt
    passhash = '\\x' + Digest::SHA512.hexdigest(salt + params['password'])
    u = { id: nid.to_i, email: params['email'], grade: params['grade'], passhash: passhash, salt: salt }
    redis.hset("users", params['email'], Oj.dump(u))
    redis.hset("subscriptions", nid.to_s, "{}")
    redirect '/login'
  end

  post '/cancel' do
    redirect '/signup'
  end

  get '/login' do
    cookies.delete("user_id")
    erb :login
  end

  post '/login' do
    if authenticate(params['email'], params['password'])
      redirect '/'
    else
      halt 403
    end
  end

  get '/logout' do
    cookies.delete("user_id")
    redirect '/login'
  end

  get '/' do
    unless cookies["user_id"]
      return redirect '/login'
    end
    erb :main, locals: {email: cookies["email"]}
  end

  get '/user.js' do
    halt 403 unless cookies["user_id"]
    erb :userjs, content_type: 'application/javascript', locals: {grade: cookies["grade"]}
  end

  get '/modify' do
    halt 403 unless cookies["user_id"]

    erb :modify, locals: {grade: cookies["grade"], email: cookies["email"]}
  end

  post '/modify' do
    id = cookies["user_id"]
    halt 403 unless id

    service = params["service"]
    token = params.has_key?("token") ? params["token"].strip : nil
    keys = params.has_key?("keys") ? params["keys"].strip.split(/\s+/) : nil
    param_name = params.has_key?("param_name") ? params["param_name"].strip : nil
    param_value = params.has_key?("param_value") ? params["param_value"].strip : nil

    arg_json = cookies["subscriptions"]
    arg = Oj.load(arg_json)
    arg[service] ||= {}
    arg[service]['token'] = token if token
    arg[service]['keys'] = keys if keys
    if param_name && param_value
      arg[service]['params'] ||= {}
      arg[service]['params'][param_name] = param_value
    end

    j = Oj.dump(arg)
    cookies["subscriptions"] = j
    redis.hset("subscriptions", id, j)
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
      if !_a || Time.parse(a["date"]) < Time.now - 3 # TODO
        _a = fetch_api("http://api.five-final.isucon.net:8988/", {}, {"zipcode" => c})
        redis.set("tenki", _a)
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
    id = cookies["user_id"]
    halt 403 unless id

    arg_json = cookies["subscriptions"]
    arg = Oj.load(arg_json)

    data = []
    arg.each_pair do |service, conf|
      data << api_req(service, conf)
    end

    content_type :json
    Oj.dump(data)
  end

  get '/initialize' do
    $init[]
  end
end
