#!/usr/bin/env bats

[[ -s "/usr/local/rvm/scripts/rvm" ]] && source "/usr/local/rvm/scripts/rvm" # Load RVM into a shell session *as a function*

rvm 1.9.3

@test "RVM works" {
  run ruby -e 'puts RUBY_VERSION'
  [ "$status" -eq 0 ]
  [ "$output" = 1.9.3 ]
}

@test "haproxy is running" {
  ps -C haproxy
  run curl -s localhost:80
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "<html><body><h1>503 Service Unavailable</h1>" ]
}
