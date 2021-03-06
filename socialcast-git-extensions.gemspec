# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "socialcast-git-extensions/version"

Gem::Specification.new do |s|
  s.name        = "socialcast-git-extensions"
  s.version     = Socialcast::Gitx::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Socialcast"]
  s.email       = ["developers@socialcast.com"]
  s.homepage    = "http://github.com/socialcast/socialcast-git-extensions"
  s.summary     = %q{git extension scripts for socialcast workflow}
  s.description = %q{GIT it done!}

  s.rubyforge_project = "socialcast-git-extensions"

  s.add_runtime_dependency 'rugged', '>= 0.23'
  s.add_runtime_dependency 'socialcast', '>= 1.4.0'
  s.add_runtime_dependency 'activesupport', '>= 4.0'
  s.add_runtime_dependency 'rest-client', '~> 2.0'
  s.add_runtime_dependency 'thor', '~> 0.19.1'
  s.add_runtime_dependency 'rake', '>= 10.3'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'pry', '~>  0.9.12.6'
  s.add_development_dependency 'webmock', '~> 2.3', '>= 2.3.1'
  s.add_development_dependency 'byebug'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
