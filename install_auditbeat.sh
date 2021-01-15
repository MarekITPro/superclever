#!/bin/bash

set -e
# e Stop if any error occurs





# check for ENV VAR BEATS_PASS
if [[ -z "${BEATS_PASS}" ]]; then
  echo "BEATS_PASS environment variable is not set/not found, skipping installation."
  exit 2
elif [ "$#" -ne 1 ]; then
  echo "Call script with tag name: e.g. install_autidbeat.sh fb-out-all"
  exit 2
else
  echo "Starting beats install with tag: $1"
  BEATS_PASSWD=$BEATS_PASS
  BEATS_TAG=$1
fi

BEATS_USER=beats_enroll
KIBANA_URL='https://6caa9776483f445997c132f2ec3d66ec.eu-west-1.aws.found.io:9243'

# version of beat to be installed
AUDITBEAT_VERSION="7.10.1"

function install_auditbeat() {
    sudo apt-get update -y && sudo apt-get install wget jq -y

    AUDITBEAT_DOWNLOAD_URL="https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-$AUDITBEAT_VERSION-amd64.deb"
    AUDITBEAT_DOWNLOAD_PATH="/tmp"

    wget -P $AUDITBEAT_DOWNLOAD_PATH $AUDITBEAT_DOWNLOAD_URL
    sudo dpkg -i $AUDITBEAT_DOWNLOAD_PATH/auditbeat-$AUDITBEAT_VERSION-amd64.deb && rm $AUDITBEAT_DOWNLOAD_PATH/auditbeat-$AUDITBEAT_VERSION-amd64.deb
}

function enroll_auditbeat() {
  # get enrollment token (valid only once-until used)
  TOKEN=$( curl -L -X POST "$KIBANA_URL/api/beats/enrollment_tokens" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -u $BEATS_USER:$BEATS_PASSWD |jq -r .results[0].item )
  if [ -z $TOKEN  ]; then
    echo "No token returned from Beats API, cannot enroll."
    exit 2
  fi

  echo "Enrolling beat"
  sudo touch /etc/auditbeat/auditbeat.yml
  #enroll using executable (this overwrites the yml config file)
  sudo /usr/bin/auditbeat enroll $KIBANA_URL "$TOKEN" --force
  echo "Enrolling complete, look up for any errors"
}

function set_tag() {
 echo "Setting up tag"
  if [[ -z "${BEATS_TAG}" ]]; then
    echo "No tagname given, skipping setting tag"
  else
    # get ID for a given tag name
    echo "Getting tag id from name"
    TAGNAME=$(curl -s -L -X GET "$KIBANA_URL/api/beats/tags/" \
    -H 'kbn-xsrf: true' \
    -u $BEATS_USER:$BEATS_PASSWD | jq -r ".list[]|select(.name==\"$BEATS_TAG\").id")

    METAUUID=$( sudo cat /var/lib/auditbeat/meta.json | jq -r '.uuid' )
    # assign tag to endpoint
    echo "Assigning tag"
    curl -L -X POST "$KIBANA_URL/api/beats/agents_tags/assignments" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    -u $BEATS_USER:$BEATS_PASSWD \
    --data-raw '{
        "assignments" : [
          { "beatId":"'"$METAUUID"'", "tag":"'"$TAGNAME"'" }
        ]
    }'
  fi
}

function start_auditbeat() {
  sudo systemctl start auditbeat
}

install_auditbeat
enroll_auditbeat
set_tag
start_auditbeat
