#!/bin/bash

set -e

domain="$1"
token="$2"

export TMPDIR=$(mktemp -d)
trap 'rm -rf ${TMPDIR}' EXIT INT TERM

export KUBECONFIG=${TMPDIR}/.kubeconfig
oc login kubernetes.default.svc.cluster.local:443 --certificate-authority=/run/secrets/kubernetes.io/serviceaccount/ca.crt --token=$token >/dev/null || exit 1

cd /var/lib/letsencrypt

# Check if existing ${domain}.crt is valid for more than 30 days
if ! [ -s ${domain}.crt ] || ! openssl x509 -checkend 2592000 -noout -in ${domain}.crt; then

  if [ -s ${domain}.crt ]; then
    # Expired certs are considered abandoned (the host no longer resolves to our loadbalancers)
    if openssl x509 -noout -checkend 0 -in ${domain}.crt; then
      echo "Renewing certificate for ${domain}"
    else
      echo "Removing expired certificate for ${domain}"
      rm -f ${domain}.crt ${domain}.csr ${domain}.key
      exit
    fi
  else
    echo "Creating certificate for ${domain}"
  fi

  projects=$(oc get project -o jsonpath='{.items[*].metadata.name}')
  for project in $projects; do
    routes=($(oc get -n ${project} routes --output="jsonpath={.items[?(@.spec.host==\"${domain}\")].metadata.name}"))
    if [ -n "${routes}" ]; then

      # Prevent certs from being added to routes that have been rejected by the router
      if [ "$(oc get route -n ${project} ${routes} --output='jsonpath={.status.ingress[*].conditions[*].status}')" == 'True' ]; then
        route=${routes}
        break
      fi

    fi
  done

  if [ -z "${route}" ]; then
    echo "You don't have access to a route for domain ${domain}" >&2
    exit 1
  fi

  [ -s account.key ] || openssl genrsa 4096 > account.key
  [ -s ${domain}.key ] || openssl genrsa 4096 > ${domain}.key
  [ -s ${domain}.csr ] || openssl req -new -sha256 -key ${domain}.key -subj "/CN=${domain}" > ${domain}.csr

  python /usr/local/letsencrypt/acme-tiny/acme_tiny.py \
    --account-key account.key \
    --csr ${domain}.csr \
    --acme-dir /srv/.well-known/acme-challenge/ > ${domain}.crt

  /usr/local/letsencrypt/bin/insert-certificate.sh \
    -h $domain \
    -c ${domain}.crt \
    -k ${domain}.key \
    -t ${token} \
    -p ${project} \
    -r ${route}

else
  echo "We already have a certificate for ${domain} which is still valid for at least 30 days."
fi
