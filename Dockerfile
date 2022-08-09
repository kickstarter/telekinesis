FROM jruby:1.7.27-jdk

RUN apt-get update -y \
    && apt-get install -y maven openjdk-8-jdk git

RUN gem install bundler -v '1.16.5'
RUN mkdir -p lib/telekinesis

COPY Gemfile *.gemspec ./
COPY lib/telekinesis/version.rb lib/telekinesis/

RUN bundle install
