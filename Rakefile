# encoding: utf-8

require 'rubygems'
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "dbox"
  gem.homepage = "http://github.com/kenpratt/dbox"
  gem.license = "MIT"
  gem.summary = "Dropbox made easy."
  gem.description = "An easy-to-use Dropbox client with fine-grained control over syncs."
  gem.email = "ken@kenpratt.net"
  gem.authors = ["Ken Pratt"]
  gem.executables = ["dbox"]
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

require 'rcov/rcovtask'
Rcov::RcovTask.new do |test|
  test.libs << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
  test.rcov_opts << '--exclude "gems/*"'
end

task :default => :test
