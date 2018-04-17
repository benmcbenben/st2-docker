#!/bin/bash

# Create htpasswd file and login to st2 using specified username/password
htpasswd -b /etc/st2/htpasswd ${ST2_USER} ${ST2_PASSWORD}

mkdir -p /root/.st2

ROOT_CONF=/root/.st2/config

touch ${ROOT_CONF}

crudini --set ${ROOT_CONF} credentials username ${ST2_USER}
crudini --set ${ROOT_CONF} credentials password ${ST2_PASSWORD}

ST2_CONF=/etc/st2/st2.conf

ST2_API_URL=${ST2_API_URL:-http://127.0.0.1:9101}
MISTRAL_BASE_URL=${MISTRAL_BASE_URL:-http://127.0.0.1:8989/v2}

crudini --set ${ST2_CONF} auth api_url ${ST2_API_URL}
crudini --set ${ST2_CONF} mistral api_url ${ST2_API_URL}
crudini --set ${ST2_CONF} mistral v2_base_url ${MISTRAL_BASE_URL}
crudini --set ${ST2_CONF} messaging url \
  amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@${RABBITMQ_HOST}:${RABBITMQ_PORT}
crudini --set ${ST2_CONF} coordination url \
  redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}
crudini --set ${ST2_CONF} database host ${MONGO_HOST}
crudini --set ${ST2_CONF} database port ${MONGO_PORT}
if [ ! -z ${MONGO_DB} ]; then
  crudini --set ${ST2_CONF} database db_name ${MONGO_DB}
fi
if [ ! -z ${MONGO_USER} ]; then
  crudini --set ${ST2_CONF} database username ${MONGO_USER}
fi
if [ ! -z ${MONGO_PASS} ]; then
  crudini --set ${ST2_CONF} database password ${MONGO_PASS}
fi

# NOTE: Only certain distros of MongoDB support SSL/TLS
#  1) enterprise versions
#  2) those built from source (https://github.com/mongodb/mongo/wiki/Build-Mongodb-From-Source)
#
#crudini --set ${ST2_CONF} database ssl True
#crudini --set ${ST2_CONF} database ssl_keyfile None
#crudini --set ${ST2_CONF} database ssl_certfile None
#crudini --set ${ST2_CONF} database ssl_cert_reqs None
#crudini --set ${ST2_CONF} database ssl_ca_certs None
#crudini --set ${ST2_CONF} database ssl_match_hostname True

MISTRAL_CONF=/etc/mistral/mistral.conf

crudini --set ${MISTRAL_CONF} DEFAULT transport_url \
  rabbit://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@${RABBITMQ_HOST}:${RABBITMQ_PORT}
crudini --set ${MISTRAL_CONF} database connection \
  postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}

# Before we run any entrypoints, we need to make sure Mongo is up, so the initial packs are registered.
while true; do
        curl ${MONGO_HOST}:${MONGO_PORT}
        if [ $? -eq 0 ]; then
            break
        else
            sleep 5s
        fi
    done

# Run custom init scripts
for f in /st2-docker/entrypoint.d/*; do
  case "$f" in
    *.sh) echo "$0: running $f"; . "$f" ;;
    *)    echo "$0: ignoring $f" ;;
  esac
  echo
done

# 1ppc: launch entrypoint-1ppc.sh via dumb-init if $ST2_SERVICE is set
if [ ! -z ${ST2_SERVICE} ]; then
  exec /dumb-init -- /st2-docker/bin/entrypoint-1ppc.sh
fi

# Ensure the base st2 nginx config is used

( cd /etc/nginx/conf.d && ln -sf st2-base.cnf st2.conf )

# If this env var is defined, we can assume we are running in a live environment.
if [ ! -z ${GIT_ADDRESS} ]; then
    # Add in SSL cert so st2 pack installs from git installs do not fail. This is only needed if
    # the git repo has an invalid cert.
    echo QUIT | openssl s_client -connect ${GIT_ADDRESS}:443 |tee /usr/local/share/ca-certificates/git_cert.crt && update-ca-certificates;
    # We need to wait for Mongodb to become ready, so the initial packs can be registered.
    # while true; do
    #     curl ${MONGO_HOST}:${MONGO_PORT}
    #     if [ $? -eq 0 ]; then
    #         break
    #     else
    #         echo test
    #         sleep 5s
    #     fi
    # done
    # We sleep for a minute, to wait until all other containers are ready
    # sleep 1m
fi

exec /sbin/init
