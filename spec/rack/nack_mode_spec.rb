require 'eventmachine'
require 'em-spec-helpers'
# hide EventMachine for now, so we can explicitly bring it back for testing
HiddenEM = EM
[:EM, :EventMachine].each {|em| Object.send :remove_const, em }

require 'rack/test'
require 'sinatra'

require 'rack/nack_mode'


class ExampleApp < Sinatra::Base
  class << self
    def shutdown
      if @health_check
        @health_check.shutdown { exit 0 }
      else
        exit 0
      end
    end

    # for testing
    def reset!
      @health_check = nil
    end
  end

  use Rack::NackMode, nacks_before_shutdown: 3 do |health_check|
    # store the middleware instance for calling #shutdown above
    @health_check = health_check
  end

  get '/info' do
    'Winds light to variable.'
  end
end


describe Rack::NackMode do
  include Rack::Test::Methods

  let :app do
    ExampleApp.new
  end

  after do
    ExampleApp.reset!
  end

  it 'should not interfere with the app' do
    get '/info'
    last_response.should be_ok
    last_response.body.should =~ /light/
  end

  describe 'health check' do
    subject { last_response }

    describe 'when the app is healthy' do
      before do
        get '/admin'
      end

      it { should be_ok }
      its(:body) { should == 'GOOD' }
    end

    describe 'when the app is shutting down' do
      before do
        ExampleApp.stub! :exit

        # Rack doesn't initialise the middleware until it gets a request; poke
        # it into action.
        get '/admin'

        ExampleApp.shutdown
        get '/admin'
      end

      it { should_not be_ok }
      its(:body) { should == 'BAD' }
    end
  end

  describe 'NACK Mode' do
    subject { ExampleApp }

    before do
      ExampleApp.stub! :exit

      # Rack doesn't initialise the middleware until it gets a request; poke it
      # into action.
      get '/admin'
    end

    it 'should not shut down as soon as asked to do so' do
      ExampleApp.should_not_receive :exit
      ExampleApp.shutdown
    end

    it 'should still not shut down after NACKing just one health check' do
      ExampleApp.should_not_receive :exit
      ExampleApp.shutdown
      get '/admin'
    end

    it 'should shut down after NACKing 3 health checks' do
      ExampleApp.should_receive :exit
      ExampleApp.shutdown
      3.times { get '/admin' }
    end

    describe 'in EventMachine' do
      before { ::EM = ::HiddenEM }
      after { Object.send :remove_const, :EM }

      it 'should not shut down immediately after NACKing 3 health checks' do
        ExampleApp.should_not_receive :exit
        ExampleApp.shutdown
        3.times { get '/admin' }
      end

      it 'should shut down one tick after NACKing 3 health checks' do
        ExampleApp.should_receive :exit
        ExampleApp.shutdown
        3.times { get '/admin' }
        EM.run_all_ticks
      end
    end
  end
end
