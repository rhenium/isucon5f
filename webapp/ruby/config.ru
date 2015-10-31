require_relative './app.rb'

use Rack::Lineprof
run Isucon5f::WebApp
