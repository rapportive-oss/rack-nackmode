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
  use Rack::NackMode, nacks_before_shutdown: 3 do |health_check|
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
   balancer it's going down before it can safely do so.  If not specified, NACK
   Mode is disabled and the app will shut down immediately when asked to do so.
 * `:logger` &ndash; middleware will log progress to this object if supplied.
