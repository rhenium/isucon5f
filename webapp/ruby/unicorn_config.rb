worker_processes 30
preload_app true
listen 8080, backlog: 4096
listen "/sock/unicorn.sock", backlog: 4096
# pid "/home/isucon/webapp/ruby/unicorn.pid"
