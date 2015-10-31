worker_processes 4
preload_app true
listen 8080
listen "/sock/unicorn.sock", backlog: 4096
# pid "/home/isucon/webapp/ruby/unicorn.pid"
