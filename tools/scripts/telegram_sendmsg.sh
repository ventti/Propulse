#!/bin/bash
set -e

MSG=${1:-${TELEGRAM_MSG}}
_ERROR=0
if [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "Error: Env variable TELEGRAM_CHAT_ID is not set."
    _ERROR=1
fi
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo "Error: Env variable TELEGRAM_BOT_TOKEN is not set."
    _ERROR=1
fi
if [ -z "$MSG" ]; then
    echo "Error: TELEGRAM_MSG is not set. Also no message provided as script argument. One of them is required."
    _ERROR=1
fi
if [ $_ERROR -eq 1 ]; then
    exit 1
fi

JSON="{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": \"${MSG}\", \"disable_notification\": true, \"no_webpage\": true}"

curl -X POST \
     -H 'Content-Type: application/json' \
     -d "${JSON}" \
     https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage