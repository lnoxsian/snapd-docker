#!/bin/sh
#
# Make sure to have docker installed before running this script!
# (Tested with recent Docker versions and Ubuntu 22.04)
#

set -e

CONTNAME=snappy
IMGNAME=snapd
RELEASE=22.04

SUDO=""
if ! groups | grep -q '\bdocker\b' && [ "$(id -u)" != "0" ]; then
    SUDO="sudo"
fi

if [ "$(which docker 2>/dev/null)" = "/snap/bin/docker" ]; then
    export TMPDIR="$(readlink -f ~/snap/docker/current)"
    /snap/bin/docker >/dev/null 2>&1 || true
fi

BUILDDIR=$(mktemp -d)

usage() {
    echo "usage: $(basename $0) [options]"
    echo
    echo "  -c|--containername <name> (default: snappy)"
    echo "  -i|--imagename <name> (default: snapd)"
    echo "  -r|--release <ubuntu release> (default: 22.04)"
    echo
    exit 0
}

print_info() {
    echo
    echo "use: $SUDO docker exec -it $CONTNAME <command> ... to run a command inside this container"
    echo
    echo "to remove the container use: $SUDO docker rm -f $CONTNAME"
    echo "to remove the related image use: $SUDO docker rmi $IMGNAME"
}

clean_up() {
    sleep 1
    $SUDO docker rm -f $CONTNAME >/dev/null 2>&1 || true
    $SUDO docker rmi $IMGNAME >/dev/null 2>&1 || true
    $SUDO docker rmi $($SUDO docker images -f "dangling=true" -q) >/dev/null 2>&1 || true
    rm_builddir
}

rm_builddir() {
    rm -rf "$BUILDDIR" || true
    exit 0
}

trap clean_up 1 2 3 4 9 15

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--containername)
            [ -n "$2" ] && CONTNAME=$2 && shift || usage ;;
        -i|--imagename)
            [ -n "$2" ] && IMGNAME=$2 && shift || usage ;;
        -r|--release)
            [ -n "$2" ] && RELEASE=$2 && shift || usage ;;
        -h|--help)
            usage ;;
        *)
            usage ;;
    esac
    shift
done

if [ -n "$($SUDO docker ps -f name=$CONTNAME -q)" ]; then
    echo "Container $CONTNAME already running!"
    print_info
    rm_builddir
fi

if ! $SUDO docker images | grep -q "$IMGNAME"; then
    cat << EOF > "$BUILDDIR/Dockerfile"
FROM ubuntu:$RELEASE

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PATH "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y fuse snapd squashfuse && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    dpkg-divert --local --rename --add /sbin/udevadm && \
    ln -s /bin/true /sbin/udevadm

# Snapd workaround for containers
RUN systemctl mask systemd-udevd.service || true

# Snapd needs /run/snapd to exist
RUN mkdir -p /run/snapd

# Start snapd as init process is not present
CMD ["/bin/bash"]
EOF
    $SUDO docker build -t $IMGNAME --force-rm=true --rm=true "$BUILDDIR" || clean_up
fi

# Start the detached container
$SUDO docker run \
    --name="$CONTNAME" \
    -ti \
    --tmpfs /run \
    --tmpfs /run/lock \
    --tmpfs /tmp \
    --cap-add SYS_ADMIN \
    --device=/dev/fuse \
    --security-opt apparmor:unconfined \
    --security-opt seccomp:unconfined \
    -d $IMGNAME || clean_up

# Start snapd in the background
$SUDO docker exec "$CONTNAME" bash -c "nohup /usr/lib/snapd/snapd &"

# Wait for snapd socket
TIMEOUT=100
SLEEP=0.1
echo -n "Waiting up to $(($TIMEOUT/10)) seconds for snapd startup "
while ! $SUDO docker exec "$CONTNAME" test -S /run/snapd.socket; do
    echo -n "."
    sleep $SLEEP || clean_up
    TIMEOUT=$(($TIMEOUT-1))
    if [ "$TIMEOUT" -le "0" ]; then
        echo " Timed out!"
        clean_up
    fi
done
echo " done"

$SUDO docker exec "$CONTNAME" snap install core --edge || clean_up
echo "container $CONTNAME started ..."

print_info
rm_builddir
