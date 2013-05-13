require 'sinatra'

require 'rack/nack_mode'

class MyApp < Sinatra::Base
  class << self
    def shutdown
      if @health_check
        @health_check.shutdown { exit! 0 }
      else
        exit! 0
      end
    end
  end

  use Rack::NackMode do |health_check|
    @health_check = health_check
  end

  post '/shutdown' do
    self.class.shutdown
  end

  get '/info' do
    'Hello'
  end
end

run MyApp
