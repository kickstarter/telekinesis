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
      version_match ||= `java -version 2>&1`.match(/jdk version "1\.(\d)\.(\d+_\d+)"/)
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
  task :build => [:have_jdk6_or_higher?, :have_maven?, :clean] do
    log_ok("Building jar") do
      Dir.chdir("ext") do
        `mkdir -p target/`
        `mvn package 2>&1 > target/build_log`
        raise "build failed. See ext/target/build_log for details" unless $?.success?
      end
    end

    Dir['target/*.jar'].each do |f|
      log_ok("Copying #{f}") do
        FileUtils.cp(f,"../lib/telekinesis/")
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
  Rake::Task["ext:build"].invoke if Dir.glob('lib/telekinesis/telekinesis*.jar').empty?
end

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList["test/**/test_*.rb"].exclude(/test_helper/)
  t.verbose = true
end
task :test => :check_for_ext
