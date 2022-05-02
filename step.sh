#!/bin/bash

THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -e

#=======================================
# Functions
#=======================================

RESTORE='\033[0m'
RED='\033[00;31m'
YELLOW='\033[00;33m'
BLUE='\033[00;34m'
GREEN='\033[00;32m'

function color_echo {
	color=$1
	msg=$2
	echo -e "${color}${msg}${RESTORE}"
}

function echo_fail {
	msg=$1
	echo
	color_echo "${RED}" "${msg}"
	exit 1
}

function echo_warn {
	msg=$1
	color_echo "${YELLOW}" "${msg}"
}

function echo_info {
	msg=$1
	echo
	color_echo "${BLUE}" "${msg}"
}

function echo_details {
	msg=$1
	echo "  ${msg}"
}

function echo_done {
	msg=$1
	color_echo "${GREEN}" "  ${msg}"
}

function validate_required_variable {
	key=$1
	value=$2
	if [ -z "${value}" ] ; then
		echo_fail "[!] Variable: ${key} cannot be empty."
	fi
}

function validate_required_input {
	key=$1
	value=$2
	if [ -z "${value}" ] ; then
		echo_fail "[!] Missing required input: ${key}"
	fi
}

function validate_required_input_with_options {
	key=$1
	value=$2
	options=$3

	validate_required_input "${key}" "${value}"

	found="0"
	for option in "${options[@]}" ; do
		if [ "${option}" == "${value}" ] ; then
			found="1"
		fi
	done

	if [ "${found}" == "0" ] ; then
		echo_fail "Invalid input: (${key}) value: (${value}), valid options: ($( IFS=$", "; echo "${options[*]}" ))"
	fi
}

function get_upload_status {
    local upload_arn="$1"
    validate_required_variable "upload_arn" $upload_arn

    local upload_status=$(aws devicefarm get-upload --arn="$upload_arn" --query='upload.status' --output=text)
    echo "$upload_status"
}

#=======================================
# Main
#=======================================

#
# Validate parameters
echo_info "Configs:"
if [[ -n "$access_key_id" ]] ; then
	echo_details "* access_key_id: ***"
else
	echo_details "* access_key_id: [EMPTY]"
fi
if [[ -n "$secret_access_key" ]] ; then
	echo_details "* secret_access_key: ***"
else
	echo_details "* secret_access_key: [EMPTY]"
fi
echo_details "* device_farm_project: $device_farm_project"
echo_details "* upload_file_path: $upload_file_path"
echo_details "* upload_type: $upload_type"
echo_details "* aws_region: $aws_region"
echo

validate_required_input "access_key_id" $access_key_id
validate_required_input "secret_access_key" $secret_access_key
validate_required_input "device_farm_project" $device_farm_project
validate_required_input "upload_file_path" $upload_file_path
validate_required_input "upload_type" $upload_type
validate_required_input "aws_region" $aws_region

export AWS_DEFAULT_REGION="${aws_region}"
export AWS_ACCESS_KEY_ID="${access_key_id}"
export AWS_SECRET_ACCESS_KEY="${secret_access_key}"

set -o nounset
set -o errexit
set -o pipefail

##### Do upload #######

echo_info 'Preparing package upload.'

# Intialize upload
upload_file_name=$(basename "$upload_file_path")
create_upload_response=$(aws devicefarm create-upload --project-arn="$device_farm_project" --name="$upload_file_name" --type="$upload_type" --query='upload.[arn, url]' --output=text)
upload_arn=$(echo $create_upload_response|cut -d' ' -f1)
upload_url=$(echo $create_upload_response|cut -d' ' -f2)
echo_details "Initialized upload of package '$upload_file_path' for package ARN '$upload_arn'"

# Perform upload
echo_details "Beginning upload"
curl -T "$upload_file_path" "$upload_url"
echo_details "Upload finished. Polling for status."

# Poll for successful upload
upload_status=$(get_upload_status "$upload_arn")
echo_details "Upload status: $upload_status"
while [ ! "$upload_status" == 'SUCCEEDED' ]; do
    if [ "$upload_status" == 'FAILED' ]; then
        echo_fail 'Upload failed!'
    fi

    echo_details "Upload not yet processed; waiting. (Status=$upload_status)"
    sleep 10
    upload_status=$(get_upload_status "$upload_arn")
done

envman add --key BITRISE_DEVICEFARM_UPLOAD_ARN --value "$upload_arn"

echo_details 'Upload successful!'
