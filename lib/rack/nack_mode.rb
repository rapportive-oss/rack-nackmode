require 'active_support/core_ext/hash/keys'

module Rack
  class NackMode
    def initialize(app, options = {})
      @app = app

      options.assert_valid_keys :on_nack, :healthy_if, :sick_if
      @health_callback = if options[:healthy_if] && options[:sick_if]
        raise ArgumentError, 'Please specify either :healthy_if or :sick_if, not both'
      elsif healthy_if = options[:healthy_if]
        healthy_if
      elsif sick_if = options[:sick_if]
        lambda { !sick_if.call }
      else
        lambda { true }
      end
      @on_nack = options[:on_nack] || lambda {}
    end

    def call(env)
      if health_check?(env)
        health_check_response(env)
      else
        @app.call(env)
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
        @on_nack.call
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
