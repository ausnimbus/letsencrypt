FROM openshift/origin

MAINTAINER AusNimbus <support@ausnimbus.com.au>

ENV HOME=/var/lib/letsencrypt

LABEL io.k8s.description="Provision and manage Letsencrypt certificates for AusNimbus." \
      io.k8s.display-name="Lets Encrypt"

EXPOSE 8080

RUN yum -y install openssl jq golang-bin dig && \
    yum clean all && \
    mkdir -p /srv/.well-known/acme-challenge /var/lib/letsencrypt && \
    chmod 775 /srv/.well-known/acme-challenge /var/lib/letsencrypt

COPY . /go/src/github.com/ausnimbus/openshift-letsencrypt/

RUN ln -s /go/src/github.com/ausnimbus/openshift-letsencrypt /usr/local/letsencrypt && \
    export GOPATH=/go && \
    cd /usr/local/letsencrypt && \
    go install github.com/ausnimbus/openshift-letsencrypt

VOLUME /var/lib/letsencrypt
ENTRYPOINT ["/go/bin/openshift-letsencrypt"]
