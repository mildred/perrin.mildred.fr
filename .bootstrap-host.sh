#!/bin/sh
# usage: bootstrap-ssh.sh dir

zero="$(basename "$0")"
usage(){
    echo "Usage: $zero [-f] [--] node_id dir" >&2
    exit 1
}

force=false
while true; do
  case "$1" in
    -f)
      force=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break;
  esac
done

if [ $# -lt 1 ]; then
    usage
fi

node_id="$1"
dir="$2"
branch="$3"
command="${4:-make}"
ver=20170531

has(){
  which "$@" >/dev/null 2>/dev/null
}

warn(){
  echo "$@" >&2
}

echo "Provisionning host bootstrap v$ver in $dir"

echo "==> Create repository in $dir"

if [ -e "$dir/.git" ]; then
  ( cd "$dir"
    current_node_id="$(cat .git/info/dops_node_id 2>/dev/null)"
    if [ "a$node_id" != "a$current_node_id" ] && [ -n "$current_node_id" ]; then
      warn
      warn "ERROR: You are bootstrapping the wrong node"
      warn "ERROR: The node you are connected to is $current_node_id"
      warn "ERROR: Use -f to override"
      exit 42
    fi
  )
fi

configure(){
  umask 0066
  cd "$1"
  GIT_DIR="$(git rev-parse --git-dir)"
  echo "Set node_id to '$node_id'"
  echo "$node_id" >"$GIT_DIR/info/dops_node_id"
  if [ -n "$branch" ] && [ master != "$branch" ]; then
    echo "Set HEAD to refs/heads/$branch"
    git symbolic-ref HEAD "refs/heads/$branch"
  fi
  cat >"$GIT_DIR/hooks/post-update" <<"EOF"
    run_provisioning(){
      unset GIT_DIR
      export LC_ALL=C
      cd ..

      echo "Provisionning in $PWD:"
      ( set -x
        umask 0066
        git reset --hard HEAD
        git submodule update --init --no-fetch --recursive --force --reference "$PWD"
      )
      echo " $(git rev-parse HEAD) . ($(git describe --all HEAD))"
      git submodule status --recursive
      t="$(tempfile 2>/dev/null || mktemp)" || exit
      trap "rm -f -- '$t'" EXIT
      ( set -x
        umask 002
        run_command >"$t" 2>&1 </dev/null
EOF
  cat >>"$GIT_DIR/hooks/post-update" <<EOF
        $command >"\$t" 2>&1 </dev/null
EOF
  cat >>"$GIT_DIR/hooks/post-update" <<"EOF"
      ) &
      tail -n 0 --pid $! -f "$t"
      rm -f -- "$t"
      trap - EXIT
    }
    
    
    HEAD="$(git symbolic-ref HEAD)"
    for ref in "$@"; do
      if [ "x$ref" = "x$HEAD" ]; then
        ( run_provisioning )
      fi
    done
EOF
  chmod +x "$GIT_DIR/hooks/post-update"
  git config receive.denyCurrentBranch false
  git config receive.denyNonFastForwards false
  git config core.sharedRepository 0600
}

if [ -e "$dir" ] && $force; then
  warn "$dir: removing (-f provided)"
  rm -rf "$dir"
fi

if [ -e "$dir/.git" ]; then
  configure "$dir"
elif [ -e "$dir" ]; then
  warn "$dir: already exists"
  exit 1
else
  mkdir -p "$dir"
  cd "$dir"
  umask 0066
  git init
  configure "."
fi

echo "Bootstrapping done."

exit 0
# kate: hl sh;

