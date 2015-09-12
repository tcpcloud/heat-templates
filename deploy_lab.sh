#!/bin/bash -e

#
# Don't forget you have to source credentials for correct lab user first!
#
# This simple script should deploy lab automatically:
#  - fix key name in env/*.env to match current lab number (if any)
#  - deploy salt_single_public
#  - fix private_net_id in env/*.env to match Salt private network
#  - deploy remaining stacks
#

NUM=$1
STACKS=("openstack_cluster_public" "openvstorage_cluster_private")
POLL_TIME=5

## Functions
exit_error() {
    echo "$1" >&2
    exit 1
}

log_info() {
    echo "[INFO] $1"
}

create_stack() {
    stack=$1

    log_info "Deploying stack ${stack}"
    ./create_stack.sh $stack >/dev/null

    state=''
    while true; do
        state=$(heat stack-list | grep $stack | awk '{print $6}')
        log_info ".. ${state}"
        if [[ "$state" == 'CREATE_FAILED' ]]; then
            exit_error "Creation of stack ${stack} failed"
        fi
        if [[ "$state" == 'CREATE_COMPLETE' ]]; then
            break
        fi
        sleep ${POLL_TIME}
    done
}

## Main
for stack in salt_single_public ${STACKS[*]}; do
    log_info "Fixing key_name in env/${stack}.env, key_name=workshop-user${NUM}-key"
    sed -i "s,key_name:.*,key_name:\ workshop-user${NUM}-key,g" env/${stack}.env
done

create_stack "salt_single_public"
NET_ID=$(nova net-list | grep workshop-net | awk '{print $2}')

for stack in ${STACKS[*]}; do
    log_info "Fixing private_net_id in env/${stack}.env, net_id=${NET_ID}"
    sed -i "s,private_net_id:.*,private_net_id:\ ${NET_ID},g" env/${stack}.env
done

for stack in ${STACKS[*]}; do
    create_stack "$stack"
done

