#!/usr/bin/env bats

[[ -s "/usr/local/rvm/scripts/rvm" ]] && source "/usr/local/rvm/scripts/rvm" # Load RVM into a shell session *as a function*

rvm 1.9.3

teardown () {
  [ -n "$app1" ] && kill -9 "$app1"
}

setup_app() {
  cp "$BATS_TEST_DIRNAME"/{Gemfile,config.ru} .
  bundle check || bundle install
}

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

@test "can bring up the app" {
  setup_app
  rackup -p 3000 &
  app1=$!
  sleep 1
  run curl -s localhost:3000/admin
  [ "$status" -eq 0 ]
  [ "$output" = GOOD ]
  kill $app1 && unset app1
}

@test "shutdown behaviour works as expected" {
  setup_app
  rackup -p 3000 &
  app1=$!
  sleep 1
  run curl -s localhost:3000/admin
  [ "$output" = GOOD ]
  curl -s -XPOST localhost:3000/shutdown -dfoo

  for i in {1..3}; do
    run curl -s localhost:3000/admin
    [ "$status" -eq 0 ]
    [ "$output" != GOOD ]
    sleep 0.5
  done

  run ps -p $app1
  echo $output
  [ "$status" -ne 0 ]
  unset app1
}
