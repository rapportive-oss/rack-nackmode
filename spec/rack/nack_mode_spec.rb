require 'eventmachine'
require 'em-spec-helpers'
# hide EventMachine for now, so we can explicitly bring it back for testing
HiddenEM = EM
[:EM, :EventMachine].each {|em| Object.send :remove_const, em }

require 'rack/test'
require 'sinatra'

require 'rack/nack_mode'


class ExampleApp < Sinatra::Base
  configure do
    @database = Struct.new(:connected).new
  end

  class << self
    attr_reader :database, :health_check

    def shutdown
      if @health_check
        @health_check.shutdown { exit 0 }
      else
        exit 0
      end
    end

    def ready_to_serve?
      database.connected
    end

    # for testing
    def reset!
      @health_check = nil
    end
  end

  use Rack::NackMode, healthy_if: method(:ready_to_serve?) do |health_check|
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

  before do
    Rack::NackMode::Timer.stub :new => mock('timer', cancel: nil)
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
        ExampleApp.database.stub! :connected => true
        get '/admin'
      end

      it { should be_ok }
      its(:body) { should == 'GOOD' }

      describe 'and the app is shutting down' do
        before do
          ExampleApp.stub! :exit

          ExampleApp.shutdown
          get '/admin'
        end

        it { should_not be_ok }
        its(:body) { should == 'BAD' }
      end
    end

    describe 'when the app is unhealthy' do
      before do
        ExampleApp.database.stub! :connected => false
        get '/admin'
      end

      it { should_not be_ok }
      its(:body) { should_not =~ /GOOD/ }

      describe 'and the app is shutting down' do
        before do
          ExampleApp.stub! :exit

          ExampleApp.shutdown
          get '/admin'
        end

        it { should_not be_ok }
        its(:body) { should == 'BAD' }
      end
    end
  end

  describe 'NACK Mode' do
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

    describe "when we don't get health checks" do
      before do
        ExampleApp.health_check.stub(:install_healthcheck_timeout) do |&timeout|
          @healthcheck_timeout = timeout
          mock('timer')
        end

        ExampleApp.shutdown
      end

      it 'should shut down after waiting long enough' do
        ExampleApp.should_receive :exit

        @healthcheck_timeout.call
      end

      it 'should clear the timeout after receiving a health check' do
        ExampleApp.health_check.should_receive(:clear_healthcheck_timeout)

        get '/admin'
      end
    end
  end
end
