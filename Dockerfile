FROM ubuntu:noble AS build-stage

ENV TZ=UTC

RUN apt-get install -y tzdata
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
COPY --from=build-stage /export /


ENTRYPOINT ["/usr/bin/tail", "-f", "/dev/null"]
