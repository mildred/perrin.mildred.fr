#!/bin/bash

cd "$(dirname "$0")"

repo_dir=
distant_host=perrin.mildred.fr
distant_user=root
distant_port=

run_file=run.sh
bootstrap_file=bootstrap.sh
: ${distant_port:=22}
: ${repo_dir:=$PWD}
: ${distant_user:=$USER}
: ${distant_dir:=/root}

while true; do
  case "$1" in
    --bootstrap|-b)
      run_file=bootstrap.sh
      shift
      ;;
    --help|-h)
      echo "$0 [-b|--bootstrap]"
      echo "$0 -h|--help"
      ;;
    *)
      break
      ;;
  esac
done

if ! ( set -x; rsync --rsh="ssh -p $distant_port" -a "$repo_dir" "$distant_user@$distant_host:$distant_dir" ); then
  echo 
  printf "%s does not seem to be bootstrapped, bootstrap? [Yn] " "$distant_host"
  if [ "n${ans//N/n}" != "nn" ]; then
    run_file=bootstrap_and_run.sh
  fi
fi

set -x
ssh -p $distant_port "$distant_user@$distant_host" "$distant_dir/${repo_dir##*/}/$run_file"
exit $?

