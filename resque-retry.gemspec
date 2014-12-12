# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'resque-retry/version'

Gem::Specification.new do |s|
  s.name = 'resque-retry'
  s.version = ResqueRetry::VERSION
  s.date = Time.now.strftime('%Y-%m-%d')
  s.authors = ['Luke Antins', 'Ryan Carver', 'Jonathan W. Zaleski']
  s.email = ['luke@lividpenguin.com']
  s.summary = 'A resque plugin; provides retry, delay and exponential backoff support for resque jobs.'
  s.description = <<-EOL
  resque-retry provides retry, delay and exponential backoff support for
  resque jobs.

  Features:

  * Redis backed retry count/limit.
  * Retry on all or specific exceptions.
  * Exponential backoff (varying the delay between retrys).
  * Multiple failure backend with retry suppression & resque-web tab.
  * Small & Extendable - plenty of places to override retry logic/settings.
  EOL
  s.homepage = 'http://github.com/lantins/resque-retry'
  s.license = 'MIT'

  s.has_rdoc = false
  s.files = `git ls-files`.split($/)
  s.require_paths = %w[lib]

  s.add_dependency('resque', '~> 1.25')
  s.add_dependency('resque-scheduler', '~> 3.0')
  s.add_dependency('damnl')
  s.add_dependency('hashie')

  s.add_development_dependency('rake', '~> 10.1')
  s.add_development_dependency('minitest', '~> 4.0')
  s.add_development_dependency('rack-test', '~> 0.6')
  s.add_development_dependency('yard', '~> 0.8')
  s.add_development_dependency('json', '~> 1.8')
  s.add_development_dependency('simplecov', '~> 0.7')
  s.add_development_dependency('mocha', '~> 1.0')
end
