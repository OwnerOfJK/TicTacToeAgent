#!/bin/bash
set -euo pipefail
pushd $(dirname "$0")/..

# Set RPC_URL with default value
RPC_URL="http://localhost:5050"

# Check if a command line argument is supplied
if [ $# -gt 0 ]; then
    # If an argument is supplied, use it as the RPC_URL
    RPC_URL=$1
fi

export WORLD_ADDRESS=$(cat ./target/dev/manifest.json | jq -r '.world.address')

export ACTIONS_ADDRESS=$(cat ./target/dev/manifest.json | jq -r '.contracts | first | .address')

echo "---------------------------------------------------------------------------"
echo world : $WORLD_ADDRESS
echo " "
echo actions : $ACTIONS_ADDRESS
echo "---------------------------------------------------------------------------"

# enable system -> component authorizations
COMPONENTS=("LastAttempt")

echo "Write permissions for ACTIONS"
for component in ${COMPONENTS[@]}; do
    sozo auth writer $component $ACTIONS_ADDRESS --world $WORLD_ADDRESS --rpc-url $RPC_URL
done
echo "Write permissions for ACTIONS: Done"

echo "Initialize ACTIONS: Done"
sleep 0.1
sozo execute --rpc-url $RPC_URL $ACTIONS_ADDRESS init
echo "Initialize ACTIONS: Done"


echo "Default authorizations have been successfully set."
