#!/bin/bash

# load our variables
# https://gist.github.com/mihow/9c7f559807069a03e302605691f85572
if [ ! -f .env ]; then
    export $(cat .env | xargs)
fi

CADDYFILE_PATH="$VOLUMES_PATH/caddy/etc/caddy"
CADDYFILE="$CADDYFILE_PATH/Caddyfile"

# check permissions for VOLUMES_PATH
FAIL_STATE=0
if [ -d $VOLUMES_PATH ]  && [ ! -w $VOLUMES_PATH ]; then
    echo "$VOLUMES_PATH exists, but cannot write into it."
    FAIL_STATE=1
elif [ ! -d $VOLUMES_PATH ] && [ ! -w $VOLUMES_PATH/.. ]; then
    echo "Don't have the permissions to create $VOLUMES_PATH."
    FAIL_STATE=1
else
    mkdir -p $VOLUMES_PATH
    # if [ $? -ne 0 ]; then
    #     echo "Could not create volumes directory at $VOLUMES_PATH."
    #   return
    # fi
fi

# check for docker-compose
if [ ! which docker-compose ]; then
    echo "docker-compose not found!"
    FAIL_STATE=1
fi

if [ FAIL_STATE -eq 1 ]; then
    return
fi

# TODO: build both private and public caddyfiles
# build the private caddyfile
if [ ! -f $VOLUMES_PATH/caddy/etc/caddy/Caddyfile ]; then
    mkdir -p $CADDYFILE_PATH

    cp private/Caddyfile $CADDYFILE

    # replace the vars in the caddyfile with the vars in env
    sed -i -e "s/TAILNET_NAME/$TAILNET/g" $CADDYFILE
    sed -i -e "s/DOMAIN_NAME/$DOMAIN_URL/g" $CADDYFILE
else
    echo "Existing Caddyfile found, skipping build."
fi

if id -nG ${whoami} | grep -qw "docker"; then
    docker-compose up -d
else
    sudo docker-compose up -d
fi
