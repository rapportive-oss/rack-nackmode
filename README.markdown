# Rack::NackMode

Middleware enabling zero-downtime maintenance behind a load balancer.

## Overview

`Rack::NackMode` adds a health check endpoint to your app that enables it to
communicate to a load balancer its ability (or lack thereof) to serve requests.
It supports a "NACK Mode" protocol, so that when your app wants to shut down, it
makes sure the load balancer knows to stop sending it requests before doing so.
It does this by responding to the health check request with a <em>n</em>egative
<em>ack</em>nowledgement (NACK) until the load balancer marks it as down.  The app can
(and should) continue to serve requests until that point.

To make this work, your app needs to inform the middleware when it wants to shut
down, and the middleware will call back when it's safe to do so.

## Usage

Basic example:

```ruby
class MyApp < Sinatra::Base
  use Rack::NackMode do |health_check|
    # store the middleware instance for calling #shutdown below
    @health_check = health_check
  end

  class << self
    def shutdown
      if @health_check # see note below
        @health_check.shutdown { exit 0 }
      else
        exit 0
      end
    end
  end
end
```

N.B. because Rack waits to initialise middleware until it receives an HTTP
request, it's possible to shut down before the middleware is initialised.
That's unlikely to be a problem, because having not received any HTTP requests,
we've obviously not received any *health check* requests either, meaning the
load balancer should already believe we're down: so it should be safe to
shutdown immediately, as in the above example.

### Configuration

The `use` statement to initialise the middleware takes the following options:

 * `:path` &ndash; path for the health check endpoint (default `/admin`)
 * Customising whether the health check reports healthy or sick (except while
   shutting down, when it will always report sick):
     * `:healthy_if` &ndash; callback that should return `true` if your app is
       able to serve requests, and `false` otherwise.
     * `:sick_if` &ndash; callback that should return `false` if your app is
       able to serve requests, and `true` otherwise.
 * `:nacks_before_shutdown` &ndash; how many times the app should tell the load
   balancer it's going down before it can safely do so.  Defaults to 3, which
   matches e.g. haproxy's default for how many failed checks it needs before
   marking a backend as down.
 * `:healthcheck_timeout` &ndash; how long (in seconds) the app should wait for
   the first health check request.  This is to avoid the app refusing to shut
   down if the load balancer is misconfigured (or absent); if it waits this
   long without seeing a single health check, it will simply shut down.  Should
   be significantly longer than your load balancer's health check interval.
   Defaults to 15 seconds, which is conservatively longer than
   haproxy's default interval.
 * `:logger` &ndash; middleware will log progress to this object if supplied.

## Testing

The RSpec specs cover most of the functionality:

    $ bundle exec rspec

### Integration testing

To really verify this works, we need to set up two instances of an app using
this middleware behind a load balancer, and fire requests at the load balancer
while taking down one of the instances.

    $ bundle exec kitchen test

You'll need [Vagrant](http://www.vagrantup.com/) installed.
