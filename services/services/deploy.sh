#!/bin/bash

# load our variables
# https://gist.github.com/mihow/9c7f559807069a03e302605691f85572
if [ ! -f .env ]; then
  export $(cat .env | xargs)
fi

# make sure we have our volumes path
if [ ! -d $VOLUMES_PATH ]; then
  mkdir -p $VOLUMES_PATH
  if [ $? -ne 0 ]; then
    echo "Could not create volumes directory at $VOLUMES_PATH."
    return
  fi
fi

# TODO: build both private and public caddyfiles
# build the private caddyfile
if [ ! -f $VOLUMES_PATH/caddy/etc/caddy/Caddyfile ]; then
  mkdir $VOLUMES_PATH/caddy/etc/caddy

  cp private/Caddyfile $VOLUMES_PATH/caddy/etc/caddy/Caddyfile

  # replace the vars in the caddyfile with the vars in env
  sed -i -e "s/TAILNET_NAME/$TAILNET/g" $VOLUMES_PATH/caddy/etc/caddy/Caddyfile
  sed -i -e "s/DOMAIN_NAME/$DOMAIN_URL/g" $VOLUMES_PATH/caddy/etc/caddy/Caddyfile
else
  echo "Existing Caddyfile found, skipping build."
fi
