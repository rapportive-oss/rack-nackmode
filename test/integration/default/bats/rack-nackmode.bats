#!/usr/bin/env bats

[[ -s "/usr/local/rvm/scripts/rvm" ]] && source "/usr/local/rvm/scripts/rvm" # Load RVM into a shell session *as a function*

rvm 1.9.3

teardown () {
  [ -n "$app1" ] && kill -9 "$app1"
  [ -n "$app2" ] && kill -9 "$app2"
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

@test "haproxy load balances between apps" {
  setup_app
  rackup -p 4000 &
  app1=$!
  rackup -p 4001 &
  app2=$!
  sleep 10 # give haproxy a chance to notice they're awake

  run curl -s localhost/info
  [ "$output" = Hello ]

  kill $app1 $app2 && unset app1 app2
  sleep 5 # give haproxy a chance to notice they're dead
}

@test "shutting down one app doesn't incur downtime" {
  setup_app
  rackup -p 4000 &
  app1=$!
  rackup -p 4001 &
  app2=$!
  sleep 10 # give haproxy a chance to notice they're awake

  run curl -s localhost/info
  [ "$output" = Hello ]

  curl -s -XPOST localhost:4000/shutdown -dfoo
  start=$(date +%s)

  while [ $[ $(date +%s) - $start < 10 ] = 1 ]; do
    run curl -s localhost/info
    echo $output
    [ "$status" -eq 0 ]
    [ "$output" = Hello ]
    sleep 0.1
  done

  run ps -p $app1
  echo $output
  [ "$status" -ne 0 ]
  unset app1

  kill $app2 && unset app2
}
