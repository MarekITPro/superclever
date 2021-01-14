#!/bin/bash

set -e
# x Print commands and their arguments as they are executed.
# e Stop if any error occurs

# check for ENV VAR BEATS_PASS
if [[ -z "${BEATS_PASS}" ]]; then
  echo "BEATS_PASS environment variable is not set/not found, skipping installation."
  exit 2
else
  BEATS_PASSWD=$BEATS_PASS
  # first param is tagname to assign to this beat
  BEATS_TAG=$1
fi

BEATS_USER=beats_enroll
KIBANA_URL='https://6caa9776483f445997c132f2ec3d66ec.eu-west-1.aws.found.io:9243'

# versions of beat to be installed
FILEBEAT_VERSION="7.10.1"

# INSTALL
sudo apt-get update -y && sudo apt-get install wget jq -y

function install_filebeat() {
    FILEBEAT_DOWNLOAD_URL="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$FILEBEAT_VERSION-amd64.deb"
    FILEBEAT_DOWNLOAD_PATH="/tmp"

    wget -P $FILEBEAT_DOWNLOAD_PATH $FILEBEAT_DOWNLOAD_URL
    sudo dpkg -i $FILEBEAT_DOWNLOAD_PATH/filebeat-$FILEBEAT_VERSION-amd64.deb && rm $FILEBEAT_DOWNLOAD_PATH/filebeat-$FILEBEAT_VERSION-amd64.deb
}

function enroll_filebeat() {
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
  #enroll using executable (this overwrites the yml config file)
  sudo /usr/bin/filebeat enroll $KIBANA_URL "$TOKEN" --force
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

function start_filebeat() {
  sudo systemctl start filebeat
}

install_filebeat
enroll_filebeat
set_tag
start_filebeat
