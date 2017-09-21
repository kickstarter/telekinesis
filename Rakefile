require 'bundler/setup'

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

namespace :ext do
  require_relative 'lib/telekinesis/version'

  desc "Cleanup all built extension"
  task :clean do
    FileUtils.rm(Dir.glob("lib/telekinesis/*.jar"))
    Dir.chdir("ext") do
      `mvn clean 2>&1`
    end
  end

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
      jdk_version, _jdk_patchlevel = version_match.captures
      if jdk_version.to_i < 6
        raise "Found #{version_match}"
      end
    end
  end

  task :update_pom_version do
    File.open('ext/pom.xml', 'r+') do |f|
      doc = Nokogiri::XML(f)
      pom_version = doc.css("project>version")

      if pom_version.text != Telekinesis::VERSION
        log_ok("Updating pom.xml version") do
          pom_version.first.content = Telekinesis::VERSION
          f.truncate(0)
          f.rewind
          f.write(doc.to_xml)
        end
      end
    end
  end

  desc "Build the Java extensions for this gem. Requires JDK6+ and Maven"
  task :build => [:have_jdk6_or_higher?, :have_maven?, :update_pom_version, :clean] do
    fat_jar = artifact_name('ext/pom.xml')
    log_ok("Building #{fat_jar}") do
      Dir.chdir("ext") do
        `mkdir -p target/`
        `mvn package 2>&1 > target/build_log`
        raise "build failed. See ext/target/build_log for details" unless $?.success?
        FileUtils.copy("target/#{fat_jar}", "../lib/telekinesis/#{fat_jar}")
      end
    end
  end
end

namespace :gem do
  desc "Build this gem"
  task :build => 'ext:build' do
    `gem build telekinesis.gemspec`
  end
end

require 'rake/testtask'

# NOTE: Tests shouldn't be run without the extension being built, but converting
#       the build task to a file task made it hard to depend on having a JDK
#       and Maven installed. This is a little kludgy but better than the
#       alternative.
task :check_for_ext do
  fat_jar = artifact_name('ext/pom.xml')
  Rake::Task["ext:build"].invoke unless File.exists?("lib/telekinesis/#{fat_jar}")
end

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList["test/**/test_*.rb"].exclude(/test_helper/)
  t.verbose = true
end
task :test => :check_for_ext

namespace :build do
  task continuous: [:test, 'gem:build']
end

task default: 'build:continuous'
