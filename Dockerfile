FROM jruby:9.1-jdk

RUN apt-get update
RUN apt-get install -y maven

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

RUN gem install nokogiri
RUN gem install shoulda-context

ADD . /usr/src/app
ADD .git /usr/src/app

RUN rake ext:build
RUN rake gem:build

CMD ["rake", "test"]
