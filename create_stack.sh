#!/bin/bash

NAME="$0"

exit_error() {
    [ -z "$1" ] || echo "$1" >&2
    exit 1
}

exit_usage() {
    exit_error "Usage: ${NAME} [STACK]"
}

[ -z "$1" ] && exit_usage
STACK_NAME=$(basename "$1" .hot)

FILE_ENV="env/${STACK_NAME}.env"
FILE_TEMPLATE="templates/${STACK_NAME}.hot"

[ ! -e "${FILE_ENV}" ] && exit_error "Environment file ${FILE_ENV} does not exist"
[ ! -e "${FILE_TEMPLATE}" ] && exit_error "Template ${FILE_TEMPLATE} does not exist"

heat stack-create -e $FILE_ENV -f $FILE_TEMPLATE ${STACK_NAME}
