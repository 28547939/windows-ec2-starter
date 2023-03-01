#!/bin/sh

set -x


export AWS_ACCESS_KEY=
export AWS_SECRET_KEY=

export REGION="us-east-1"
export RUN_TIME=$((60 * 60 * 2))


# KEYPATH is the path to the SSH key that the user has uploaded to AWS
#   and specified for use in encrypting the login password made available
#   by AWS
#   KEYNAME is the name of the key, as it exists on AWS
export KEYPATH=""
export KEYNAME="windows-0"


./start.pl


