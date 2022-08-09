$:.push File.expand_path("../lib", __FILE__)
require "telekinesis/version"

Gem::Specification.new do |spec|
  spec.name         = "telekinesis"
  spec.version      = Telekinesis::VERSION
  spec.author       = "Ben Linsay"
  spec.email        = "ben@kickstarter.com"
  spec.summary      = "High level clients for Amazon Kinesis"
  spec.homepage     = "https://github.com/kickstarter/telekinesis"

  spec.platform     = "java"
  spec.files        = `git ls-files`.split($/) + Dir.glob("lib/telekinesis/*.jar")
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 11.3.0"
  spec.add_development_dependency "nokogiri"
  spec.add_development_dependency "minitest", "~> 5.10.3"
  spec.add_development_dependency "shoulda-context", "~> 1.2.2"
end
