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
  #       use Rack::NackMode do |health_check|
  #         # store the middleware instance for calling #shutdown below
  #         @health_check = health_check
  #       end
  #
  #       class << self
  #         def shutdown
  #           if @health_check
  #             @health_check.shutdown { exit 0 }
  #           else
  #             exit 0
  #           end
  #         end
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
    # Default number of health checks we NACK before shutting down.  This
    # matches e.g. haproxy's default for how many failed checks it needs before
    # marking a backend as down.
    DEFAULT_NACKS_BEFORE_SHUTDOWN = 3

    # Default time (in seconds) during shutdown to wait for the first
    # healthcheck request before concluding that the healthcheck is missing or
    # misconfigured, and shutting down anyway.
    DEFAULT_HEALTHCHECK_TIMEOUT = 15

    def initialize(app, options = {})
      @app = app

      options.assert_valid_keys :path,
                                :healthy_if,
                                :sick_if,
                                :nacks_before_shutdown,
                                :healthcheck_timeout,
                                :logger
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
      @nacks_before_shutdown = options[:nacks_before_shutdown] || DEFAULT_NACKS_BEFORE_SHUTDOWN
      raise ArgumentError, ":nacks_before_shutdown must be at least 1" unless @nacks_before_shutdown >= 1
      @healthcheck_timeout = options[:healthcheck_timeout] || DEFAULT_HEALTHCHECK_TIMEOUT
      @logger = options[:logger]

      yield self if block_given?
    end

    def call(env)
      if health_check?(env)
        clear_healthcheck_timeout
        health_check_response(env)
      else
        @app.call(env)
      end
    end

    def shutdown(&block)
      info "Shutting down after NACKing #@nacks_before_shutdown health checks"
      @shutdown_callback = block

      install_healthcheck_timeout { do_shutdown }

      nil
    end

    private
    def install_healthcheck_timeout
      clear_healthcheck_timeout # avoid several timers if #shutdown called twice

      @healthcheck_timer = Timer.new(@healthcheck_timeout) do
        warn "Gave up waiting for a health check after #{@healthcheck_timeout}s; bailing out."
        yield
      end
    end

    def clear_healthcheck_timeout
      return unless @healthcheck_timer
      @healthcheck_timer.cancel
      @healthcheck_timer = nil
    end

    def health_check?(env)
      env['PATH_INFO'] == @path && env['REQUEST_METHOD'] == 'GET'
    end

    def health_check_response(env)
      if shutting_down?
        @nacks_before_shutdown -= 1
        if @nacks_before_shutdown <= 0
          if defined?(EM)
            EM.next_tick do
              do_shutdown
            end
          else
            do_shutdown
          end
        else
          info "Waiting for #@nacks_before_shutdown more health checks"
        end
        respond_sick
      elsif healthy?
        respond_healthy
      else
        respond_sick
      end
    end

    def shutting_down?
      @shutdown_callback
    end

    def do_shutdown
      info 'Shutting down'
      @shutdown_callback.call
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

    def warn(*args)
      @logger.warn(*args) if @logger
    end

    module Timer
      def self.new(timeout)
        if defined?(EM)
          EMTimer.new(timeout) { yield }
        else
          ThreadTimer.new(timeout) { yield }
        end
      end

      class EMTimer
        def initialize(timeout)
          @timer = EM.add_timer(timeout) { yield }
        end

        def cancel
          EM.cancel_timer(@timer)
        end
      end

      class ThreadTimer
        def initialize(timeout)
          @thread = Thread.new do
            waited = sleep(timeout)
            # if we woke up early, waited < timeout
            if waited >= timeout
              yield
            end
          end
        end

        def cancel
          @thread.run # will wake up early from sleep
        end
      end
    end
  end
end
