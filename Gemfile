source 'https://rubygems.org'

gemspec

gem 'eventmachine' # not in gemspec because it's optional

group :integration do
  gem 'test-kitchen', git: 'git://github.com/opscode/test-kitchen.git', branch: '1.0'
  gem 'kitchen-vagrant'
  gem 'berkshelf', '>= 1.4.3' # to avoid incompatible dependencies with test-kitchen
end
