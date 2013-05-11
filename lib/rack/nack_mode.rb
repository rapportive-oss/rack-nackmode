require 'active_support/core_ext/hash/keys'

module Rack
  class NackMode
    def initialize(app, options = {})
      @app = app

      options.assert_valid_keys :healthy_if, :sick_if, :nacks_before_shutdown
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
        @shutdown_callback = block
      else
        block.call
      end
    end

    private
    def health_check?(env)
      env['PATH_INFO'] == '/admin' && env['REQUEST_METHOD'] == 'GET'
    end

    def health_check_response(env)
      if healthy?
        respond_healthy
      else
        if @shutdown_callback && @nacks_before_shutdown
          @nacks_before_shutdown -= 1
          if @nacks_before_shutdown <= 0
            @shutdown_callback.call
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
      [503, {}, ['BAD']]
    end
  end
end
