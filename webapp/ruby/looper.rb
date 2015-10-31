require 'oj'
require 'httpclient'
require 'openssl'
require "redis"

def fetch_api(uri, headers, params)
  @client ||= HTTPClient.new
  if uri.start_with? "https://"
    @client.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
  @client.get_content(uri, params, headers)
end

tenki = Thread.new {
  redis = Redis.new(host: ENV["REDIS_IP"])
  loop do
    p _a = fetch_api("http://api.five-final.isucon.net:8988/", {}, {})
    redis.set("tenki", _a)
    sleep 1
  end
}

attacked = Thread.new {
}

tenki.join
attacked.join
