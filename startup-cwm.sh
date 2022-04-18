#!/bin/bash

# Set the location of CWM config file.
CWM_CONFIGFILE=/root/guest.conf

# Set the location of provisioning error log for CWM.
CWM_ERRORFILE=/root/guest.errlog

# Set the location of generated description 
CWM_DESCFILE=/root/description.txt

# Set the location of generated install log
CWM_LOGDIR=/root

# skip cwm related steps if config file not found
if [ ! -f "$CWM_CONFIGFILE" ]; then
    #Missing CWM config file. Skipping.
    return 0
fi

function getServerIP() {

    if [ ! -f "$CWM_CONFIGFILE" ]; then

        hostname -I | awk '{print $1}'
        return 0

    fi

    if [ ! -z "$CWM_WANNICIDS" ]; then

        typeset -a "cwm_wan_ids=($CWM_WANNICIDS)"
        local mainip=$(echo "CWM_IP${cwm_wan_ids[0]}")
        echo "${!mainip}"
        return 0

    fi

    if [ ! -z "$CWM_LANNICIDS" ]; then

        typeset -a "cwm_lan_ids=($CWM_LANNICIDS)"
        local mainip=$(echo "CWM_IP${cwm_lan_ids[0]}")
        echo "${!mainip}"
        return 0

    fi

}

CONFIG=$(cat $CWM_CONFIGFILE)
STD_IFS=$IFS
IFS=$'\n'
for d in $CONFIG; do
    key=$(echo $d | cut -f1 -d"=")
    value=$(echo $d | cut -f2 -d"=")
    export "CWM_${key^^}"="$value"
done
IFS=$STD_IFS
export ADMINEMAIL=$CWM_EMAIL
export ADMINPASSWORD="$CWM_PASSWORD"
mapfile -t wan_nicids < <(cat $CWM_CONFIGFILE | grep ^vlan.*=wan-.* | cut -f 1 -d"=" | cut -f 2 -d"n")
export CWM_WANNICIDS="$(printf '%q ' "${wan_nicids[@]}")"
mapfile -t lan_nicids < <(cat $CWM_CONFIGFILE | grep ^vlan.*=lan-.* | cut -f 1 -d"=" | cut -f 2 -d"n")
[[ ! -z "$lan_nicids" ]] && export CWM_LANNICIDS="$(printf '%q ' "${lan_nicids[@]}")"
export CWM_UUID=$(cat /sys/class/dmi/id/product_serial | cut -d '-' -f 2,3 | tr -d ' -' | sed 's/./&-/20;s/./&-/16;s/./&-/12;s/./&-/8')
export CWM_SERVERIP="$(getServerIP)"
export CWM_DISPLAYED_ADDRESS=${CWM_SERVERIP}
export CWM_DOMAIN="${CWM_SERVERIP//./-}.cloud-xip.io"

# Append the following line to description file
function descriptionAppend() {

    echo "$1" >>$CWM_DESCFILE
    echo "Adding to system description file: $1" | log
    chmod 600 $CWM_DESCFILE

}

# Append command stdout to error log
function log() {

    logScriptName=$(basename $0)

    if [ ! -d "$CWM_LOGDIR" ]; then

        mkdir -p $CWM_LOGDIR

    fi

    while IFS= read -r line; do

        printf '[%s] %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$logScriptName" "$line"

    done | tee -a $CWM_LOGDIR/$(date '+%Y-%m-%d').log ${1:+${CWM_ERRORFILE}}

}

# Get current server description from CWM
function getServerDescription() {

    description=$(curl --location -f --retry-connrefused --retry 3 --retry-delay 2 -H "AuthClientId: ${CWM_APICLIENTID}" -H "AuthSecret: ${CWM_APISECRET}" "https://$CWM_URL/svc/server/$CWM_UUID/overview" | grep -Po '(?<="description":")(.*?)(?=",")')

    local exitCode=$?
    if [ $exitCode -ne 0 ]; then

        echo "Error retrieving server overview" | log 1
        return 1

    fi

    echo -e $description

}

function appendServerDescription() {

    description=$(getServerDescription)
    fulltext=$(echo -e "$description\\n$1")
    updateServerDescription "$fulltext"

}

function appendServerDescriptionTXT() {

    description=$(getServerDescription)
    uploadText=$description

    if [[ ! -z "$CWM_GUESTDESCRIPTION" && $(noWhitespace "$CWM_GUESTDESCRIPTION") != $(noWhitespace "$description") ]]; then

        uploadText=$CWM_GUESTDESCRIPTION

    fi

    if [ -f "$CWM_DESCFILE" ]; then

        fileContent=$(cat $CWM_DESCFILE)
        uploadText=$(echo -e "$uploadText\\n\\n$fileContent")

    fi


    fulltext=$(echo -e "$description\\n\\n$fileContent")
    updateServerDescription "$fulltext"
    updateServerDescription "$fileContent"
    updateServerDescription "$uploadText"

}

# Update server description in CWM according to description file
function updateServerDescription() {

    APICLIENTID=$(cat ~/guest.conf | grep Client | cut -f 2 -d"=")
    APISECRET=$(cat ~/guest.conf | grep Secret | cut -f 2 -d"=")
    CONSOLEURL=$(cat ~/guest.conf | grep url | cut -f 2 -d"=")
    VMUUID=$(cat ~/guest.conf | grep serverid | cut -f 2 -d"=")
    fileContent=$(cat $CWM_DESCFILE)
    uploadText=$(echo -e "$uploadText\\n\\n$fileContent")

    curl --location -f -X PUT --retry-connrefused --retry 3 --retry-delay 2 -H "AuthClientId: ${APICLIENTID}" -H "AuthSecret: ${APISECRET}" "https://${CONSOLEURL}/svc/server/${VMUUID}/description" --data-urlencode $'description='"${uploadText}"

    local exitCode=$?
    if [ $exitCode -ne 0 ]; then

        echo "Error updating server description" | log 1
        return 1

    fi

    echo "Updated Overview->Description data for $CWM_UUID" | log

}

# Wait for specified exitcode, exit if not equal to result
function waitOrStop() {

    local exitCode=${PIPESTATUS[0]}
    waitExitCode=$1

    if [ $waitExitCode -ne $exitCode ]; then

        echo "ExitCode $exitCode (expecting $waitExitCode). ${2:-Undefined error.}" | log 1
        exit 1

    fi

}

# Get all server IP's
function getServerIPAll() {

    if [ ! -f "$CWM_CONFIGFILE" ]; then

        hostname -I
        return 0

    fi

    echo $(cat $CWM_CONFIGFILE | grep ^ip.*=* | cut -f 2 -d"=")

}

# Function: format string to proper JSON, ONLY works with following scheme:
#
# JSON_STRING='{
# "arg1":"quoted value",
# "arg2":nonQuotedValue,
# "arg3":'$NON_QUOTED_VAR',
# "arg4":"'"$QOUTED_VAR"'"
# }'
# curl -X POST -H "Content-Type: application/json" --url "$URL" -d "$(jsonize "$JSON_STRING")"
function jsonize() {

    echo $1 | sed s'/, "/,"/g' | sed s'/{ /{/g' | sed s'/ }/}/g'

}

# function apt() {

#     if [ -x "$(command -v apt-fast)" ]; then

#         command apt-fast "$@"

#     else

#         command apt "$@"

#     fi

# }

# run action multiple times and analyze its output, return fail if found
# all params are required
# example: execSpecial 3 'error' [COMMAND]
function execSpecial() {

    local times=$1
    local filter=$2
    local action="${@:3}"
    local ok=1
    local n=0
    until [ $n -ge $times ]; do

        if eval $action | grep -q -E $filter; then

            n=$(($n + 1))
            sleep 10

        else

            ok=0
            break

        fi

    done

    return $ok

}

# fail install if cwm api key or secret is missing
if [ -z "$CWM_NO_API_KEY" ] && [[ -z "$CWM_APICLIENTID" || -z "$CWM_APISECRET" ]]; then

    echo "No CWM API Client ID or Secret is set. Exiting." | tee -a ${CWM_ERRORFILE}
    exit 1

fi
