require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'
require 'rubygems'

manifest = File.readlines('manifest').map! { |x| x.chomp! }

spec = Gem::Specification.new do |s|
  s.name = %q{dropbox}
  s.version = '1.0'

  s.authors = ["Dropbox, Inc."]
  s.date = Time.now.utc.strftime('%Y-%m-%d')
  s.description = "Dropbox REST API Client Library"
  s.email = %q{support@dropbox.com}
  s.executables = %w()
  s.extensions = %w()

  s.files = manifest
  s.homepage = %q{http://developers.dropbox.com/}

  summary = %q{Dropbox REST API Client Library}
  s.require_paths = %w(lib)
  s.summary = summary
end

task :default => [:test_units]

desc "Run basic tests"
Rake::TestTask.new("test_units") { |t|
  t.pattern = 'test/*_test.rb'
  t.verbose = true
  t.warning = true
}

Rake::GemPackageTask.new(spec) do |pkg|
    pkg.need_zip = true
    pkg.need_tar = true
end


