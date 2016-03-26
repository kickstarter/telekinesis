source 'https://rubygems.org'
gemspec

# Trigger LockJar to run when Bundler finishes to create the Jarfile.lock
@@check ||= at_exit do
  require 'lock_jar/bundler'
  LockJar::Bundler.lock!
end
