Gem::Specification.new do |gem|
  gem.name = 'rack-nackmode'
  gem.version = '0.1.0'

  gem.summary = 'Middleware for zero-downtime maintenance behind a load balancer'
  gem.description = <<-DESC
Middleware that communicates impending shutdown to a load balancer via NACKing
(negative acking) health checks.  Provided you have at least two load-balanced
instances, this allows you to shut down or restart an instance without dropping
any requests.

Your app needs to inform the middleware when it wants to shut down, and the
middleware will call back when it's safe to do so.
  DESC

  gem.authors = ['Sam Stokes']
  gem.email = %w(sam@rapportive.com)
  gem.homepage = 'http://github.com/rapportive-oss/rack-nackmode'


  gem.add_dependency 'activesupport'


  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'em-spec-helpers'
  gem.add_development_dependency 'rack-test'
  gem.add_development_dependency 'sinatra'


  gem.files = Dir['lib/**/*'] & %x{git ls-files -z}.split("\0")
end
