FROM ubuntu:noble AS build-stage

ENV TZ=UTC
# A UTF-8 locale for the package builds. courier-authlib 0.73.2 runs its test
# suite during debuild, and under the image's default C locale its
# internationalised-address tests fail: courier-unicode takes its default
# charset from the locale, and "Hóla" came out as raw UCS-4 (H\xF3\0\0\0la)
# instead of UTF-8.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# The authlib testsuite then sets LC_ALL=en_US.UTF-8 itself, overriding the
# above, so that specific locale has to exist; noble does not ship it
# generated ("setlocale: LC_ALL: cannot change locale (en_US.UTF-8)").
RUN apt-get update && apt-get install -y tzdata locales && \
    locale-gen en_US.UTF-8
RUN ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo UTC > /etc/timezone

RUN apt-get update 

COPY install-scripts/* /tmp/

RUN mkdir /export

RUN bash /tmp/packages.sh

RUN bash /tmp/install-sysconf.sh

RUN bash /tmp/install-unicode.sh

RUN bash /tmp/install-auth.sh

RUN bash /tmp/install-courier.sh

# From now on, use new scripts/things to avoid re-building.

FROM scratch AS export-stage
COPY --from=build-stage /export /export


ENTRYPOINT ["/usr/bin/tail", "-f", "/dev/null"]
