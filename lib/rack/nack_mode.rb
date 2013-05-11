require 'active_support/core_ext/hash/keys'

module Rack
  # Middleware that communicates impending shutdown to a load balancer via
  # NACKing (negative acking) health checks.  Your app needs to inform the
  # middleware when it wants to shut down, and the middleware will call back
  # when it's safe to do so.
  #
  # Responds to health checks on /admin (configurable via :path option).
  #
  # Basic usage:
  #     class MyApp < Sinatra::Base
  #       class << self
  #         def shutting_down?
  #           @shutting_down
  #         end
  #
  #         def shutdown
  #           @shutting_down = true
  #
  #           if @health_check
  #             @health_check.shutdown { exit 0 }
  #           else
  #             exit 0
  #           end
  #         end
  #       end
  #
  #       use Rack::NackMode, sick_if: method(:shutting_down?), nacks_before_shutdown: 3 do |health_check|
  #         # store the middleware instance for calling #shutdown above
  #         @health_check = health_check
  #       end
  #     end
  #
  # N.B. because Rack waits to initialise middleware until it receives an HTTP
  # request, it's possible to shut down before the middleware is initialised.
  # That's unlikely to be a problem, because having not received any HTTP
  # requests, we've obviously not received any *health check* requests either,
  # meaning the load balancer should already believe we're down: so it should
  # be safe to shutdown immediately, as in the above example.
  class NackMode
    def initialize(app, options = {})
      @app = app

      options.assert_valid_keys :path, :healthy_if, :sick_if, :nacks_before_shutdown, :logger
      @path = options[:path] || '/admin'
      @health_callback = if options[:healthy_if] && options[:sick_if]
        raise ArgumentError, 'Please specify either :healthy_if or :sick_if, not both'
      elsif healthy_if = options[:healthy_if]
        healthy_if
      elsif sick_if = options[:sick_if]
        lambda { !sick_if.call }
      else
        lambda { true }
      end
      @nacks_before_shutdown = options[:nacks_before_shutdown]
      @logger = options[:logger]

      yield self if block_given?
    end

    def call(env)
      if health_check?(env)
        health_check_response(env)
      else
        @app.call(env)
      end
    end

    def shutdown(&block)
      if @nacks_before_shutdown
        info "Shutting down after NACKing #@nacks_before_shutdown health checks"
        @shutdown_callback = block
      else
        info 'Shutting down'
        block.call
      end
    end

    private
    def health_check?(env)
      env['PATH_INFO'] == @path && env['REQUEST_METHOD'] == 'GET'
    end

    def health_check_response(env)
      if healthy?
        respond_healthy
      else
        if @shutdown_callback && @nacks_before_shutdown
          @nacks_before_shutdown -= 1
          if @nacks_before_shutdown <= 0
            info 'Shutting down'
            @shutdown_callback.call
          else
            info "Waiting for #@nacks_before_shutdown more health checks"
          end
        end
        respond_sick
      end
    end

    def healthy?
      @health_callback.call
    end

    def respond_healthy
      [200, {}, ['GOOD']]
    end

    def respond_sick
      info 'Telling load balancer we are sick'
      [503, {}, ['BAD']]
    end

    def info(*args)
      @logger.info(*args) if @logger
    end
  end
end
