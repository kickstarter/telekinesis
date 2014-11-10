require 'bundler/setup'
require_relative 'lib/telekinesis/version'

VERSION = Telekinesis::VERSION

Bundler.require(:development)

def log_ok(message)
  $stderr.write "#{message}... "
  begin
    yield
    $stderr.puts "ok"
  rescue => e
    $stderr.puts "failed"
    abort <<-EOF

error: #{e}
    EOF
  end
end

def artifact_name(path)
  File.open(path) do |f|
    doc = Nokogiri::XML(f)
    id = doc.css("project>artifactId").text
    version = doc.css("project>version").text
    "#{id}-#{version}.jar"
  end
end

namespace :build do
  task :have_maven? do
    log_ok("Checking for maven") do
      `which mvn`
      raise "Maven is required to build this gem" unless $?.success?
    end
  end

  task :have_jdk6_or_higher? do
    log_ok("Checking that at least java 6 is installed") do
      version_match = `java -version 2>&1`.match(/java version "1\.(\d)\.(\d+_\d+)"/)
      if version_match.nil?
        raise "Can't parse Java version!"
      end
      _, jdk_version, _ = version_match.captures
      if jdk_version.to_i < 8
        raise "Found #{version_match}"
      end
    end
  end

  desc "Build the Java extensions for this gem. Requires JDK6+ and Maven"
  task :ext => [:have_jdk6_or_higher?, :have_maven?] do
    fat_jar = artifact_name('ext/pom.xml')
    log_ok("Building #{fat_jar}") do
      Dir.chdir("ext") do
        `mvn clean package`
        FileUtils.copy("target/#{fat_jar}", "../lib/telekinesis/#{fat_jar}")
      end
    end
  end

  desc "Build this gem"
  task :gem => :ext do
    `gem build telekinesis.gemspec`
  end
end

# TODO:
# - Task to update the version in pom.xml to Kinesis::VERSION
# - Namespaces?


require 'rake/testtask'

Rake::TestTask.new do |t|
  t.test_files = FileList["test/test_*.rb"].exclude(/test_helper/)
  t.verbose = true
end
