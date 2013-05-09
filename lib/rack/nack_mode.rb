require 'active_support/core_ext/hash/keys'

module Rack
  class NackMode
    def initialize(app, options = {}, &health_callback)
      @app = app
      @health_callback = health_callback || lambda { true }

      options.assert_valid_keys :on_nack
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
