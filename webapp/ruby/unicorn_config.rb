worker_processes 10
preload_app true
listen 8080
listen "/sock/unicorn.sock", backlog: 4096
# pid "/home/isucon/webapp/ruby/unicorn.pid"
