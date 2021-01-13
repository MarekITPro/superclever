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

# version of beat to be installed
METRICBEAT_VERSION="7.10.1"

# INSTALL
sudo apt-get update -y && sudo apt-get install wget jq -y

function install_metricbeat() {
    METRICBEAT_DOWNLOAD_URL="https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-$METRICBEAT_VERSION-amd64.deb"
    METRICBEAT_DOWNLOAD_PATH="/tmp"

    wget -P $METRICBEAT_DOWNLOAD_PATH $METRICBEAT_DOWNLOAD_URL
    sudo dpkg -i $METRICBEAT_DOWNLOAD_PATH/metricbeat-$METRICBEAT_VERSION-amd64.deb && rm $METRICBEAT_DOWNLOAD_PATH/metricbeat-$METRICBEAT_VERSION-amd64.deb
}      

function enroll_metricbeat() {
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
  sudo /usr/bin/metricbeat enroll $KIBANA_URL "$TOKEN" --force
  echo "Enrolling complete, look up for any errors"
}

function set_tag() {
   echo "Setting up tag"
  if [[ -z "${BEATS_TAG}" ]]; then
    echo "No tagname given, skipping setting tag"
  else
    # get ID for a given tag name
    TAGNAME=$(curl -L -X GET "$KIBANA_URL/api/beats/tags/" \
    -H 'kbn-xsrf: true' \
    -u $BEATS_USER:$BEATS_PASSWD | jq -r ".list[]|select(.name==\"$BEATS_TAG\").id")

    METAUUID=$( sudo cat /var/lib/metricbeat/meta.json | jq -r '.uuid' )
    # assign tag to endpoint
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

function start_metricbeat() {
  sudo systemctl start metricbeat
}       

install_metricbeat
enroll_metricbeat
set_tag
start_metricbeat
