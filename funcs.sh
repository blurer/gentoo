#!/bin/bash

check_args() {
  if [[ "$1" -ne "$2" ]]; then
    echo "check_args error, number of given arguments was $1, must be $2!"
    exit 1
  fi
}

log_msg() {
  check_args "$#" "2"

  echo "$(date '+%d/%m/%Y %H:%M:%S') $1: $2"
}

prompt_accept() {
  check_args "$#" "1"

  read -p "$1: " choice
  case "$choice" in
    y|Y|yes|YES ) echo "y";;
    n|N|no|NO ) echo "n";;
    * ) echo "n";;
  esac
}

prompt_value() {
  check_args "$#" "2"

  read -p "$1 ('.' for default: '$2'): " value

  if [[ "$value" == "." ]]; then
    echo $2
  else
    echo $value
  fi
}
