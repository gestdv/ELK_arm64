################################################################################
# This Dockerfile was generated from the template at:
#   src/dev/build/tasks/os_packages/docker_generator/templates/Dockerfile
#
# Beginning of multi stage Dockerfile
################################################################################

################################################################################
# Build stage 0 `builder`:
# Extract Kibana artifact
################################################################################

#FROM debian:latest
FROM centos:8 AS builder

ENV KIBANA_VERSION 7.10.2
ENV NODEJS_VERSION 10.23.1

# Update CentOS and Add tar and gzip
RUN yum update -y && yum upgrade -y
RUN yum install -y tar gzip && yum clean all

RUN cd /opt && \
  curl --retry 8 -L https://artifacts.elastic.co/downloads/kibana/kibana-${KIBANA_VERSION}-linux-aarch64.tar.gz -o kibana-${KIBANA_VERSION}.tar.gz && \
  cd -
RUN mkdir /usr/share/kibana
WORKDIR /usr/share/kibana
RUN tar --strip-components=1 -zxf /opt/kibana-${KIBANA_VERSION}.tar.gz


# Remove packaged Node version
RUN rm -rf /usr/share/kibana/node
RUN mkdir /usr/share/kibana/node

# Download & Extract compatiable Node version
RUN curl -L -O https://nodejs.org/dist/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-linux-arm64.tar.xz
RUN tar -xJvf node-v${NODEJS_VERSION}-linux-arm64.tar.xz

# Move new Node version to Kibana directory
RUN mv ./node-v${NODEJS_VERSION}*/* /usr/share/kibana/node
RUN rm -rf node-v${NODEJS_VERSION}

# Ensure that group permissions are the same as user permissions.
# This will help when relying on GID-0 to run Kibana, rather than UID-1000.
# OpenShift does this, for example.
# REF: https://docs.openshift.org/latest/creating_images/guidelines.html
RUN chmod -R g=u /usr/share/kibana
RUN find /usr/share/kibana -type d -exec chmod g+s {} \;

################################################################################
# Build stage 1 (the actual Kibana image):
#
# Copy kibana from stage 0
# Add entrypoint
################################################################################
FROM centos:8
EXPOSE 5601

ENV DUMBINIT_VERSION 1.2.5

RUN for iter in {1..10}; do \
      yum update --setopt=tsflags=nodocs -y && \
      yum install --setopt=tsflags=nodocs -y \
        fontconfig freetype shadow-utils && \
      yum clean all && exit_code=0 && break || exit_code=$? && echo "yum error: retry $iter in 10s" && \
      sleep 10; \
    done; \
    (exit $exit_code)
# RUN yum update -y && yum upgrade -y && yum install -y fontconfig freetype shadow-utils && yum clean all
#RUN mv kibana-7.10.2-linux-aarch64 kibana;

# Add an init process, check the checksum to make sure it's a match
RUN curl -L -o /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_aarch64
RUN echo "b7d648f97154a99c539b63c55979cd29f005f88430fb383007fe3458340b795e  /usr/local/bin/dumb-init" | sha256sum -c -
RUN chmod +x /usr/local/bin/dumb-init

RUN mkdir /usr/share/fonts/local
RUN curl -L -o /usr/share/fonts/local/NotoSansCJK-Regular.ttc https://github.com/googlefonts/noto-cjk/raw/NotoSansV2.001/NotoSansCJK-Regular.ttc
RUN echo "5dcd1c336cc9344cb77c03a0cd8982ca8a7dc97d620fd6c9c434e02dcb1ceeb3  /usr/share/fonts/local/NotoSansCJK-Regular.ttc" | sha256sum -c -
RUN fc-cache -v


# Bring in Kibana from the initial stage.
COPY --from=builder --chown=1000:0 /usr/share/kibana /usr/share/kibana
WORKDIR /usr/share/kibana
RUN ln -s /usr/share/kibana /opt/kibana

ENV ELASTIC_CONTAINER true
ENV PATH=/usr/share/kibana/bin:$PATH

# Set some Kibana configuration defaults.
COPY --chown=1000:0 ./config/kibana.yml /usr/share/kibana/config/kibana.yml


# Add the launcher/wrapper script. It knows how to interpret environment
# variables and translate them to Kibana CLI options.
COPY --chown=1000:0 ./bin/kibana-docker /usr/local/bin/


# Ensure gid 0 write permissions for OpenShift.
RUN chmod g+ws /usr/share/kibana && \
    find /usr/share/kibana -gid 0 -and -not -perm /g+w -exec chmod g+w {} \;

# Remove the suid bit everywhere to mitigate "Stack Clash"
RUN find / -xdev -perm -4000 -exec chmod u-s {} +

# Provide a non-root user to run the process.
RUN groupadd --gid 1000 kibana && \
    useradd --uid 1000 --gid 1000 \
      --home-dir /usr/share/kibana --no-create-home \
      kibana

LABEL org.label-schema.name="Kibana" \
  org.label-schema.build-date="2021-01-13T02:23:45.910Z" \
  org.label-schema.license="Elastic License" \
  org.label-schema.schema-version="1.0" \
  org.label-schema.url="https://www.elastic.co/products/kibana" \
  org.label-schema.usage="https://www.elastic.co/guide/en/kibana/reference/index.html" \
  org.label-schema.vcs-ref="a0b793698735eb1d0ab1038f8e5d7a951524e929" \
  org.label-schema.vcs-url="https://github.com/elastic/kibana" \
  org.label-schema.vendor="Elastic" \
  org.label-schema.version="7.10.2" \
  org.opencontainers.image.created="2021-01-13T02:23:45.910Z" \
  org.opencontainers.image.documentation="https://www.elastic.co/guide/en/kibana/reference/index.html" \
  org.opencontainers.image.licenses="Elastic License" \
  org.opencontainers.image.revision="a0b793698735eb1d0ab1038f8e5d7a951524e929" \
  org.opencontainers.image.source="https://github.com/elastic/kibana" \
  org.opencontainers.image.title="Kibana_arm64" \
  org.opencontainers.image.url="https://www.elastic.co/products/kibana" \
  org.opencontainers.image.vendor="Elastic" \
  org.opencontainers.image.version="7.10.2"

USER kibana
# WORKDIR /opt/kibana
ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]

CMD ["/usr/local/bin/kibana-docker"]
# CMD /opt/kibana/bin/kibana