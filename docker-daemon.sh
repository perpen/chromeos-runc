#!/bin/sh -ex
## Run docker daemon in ChromeOS. The docker binary used to work fine but
## at some point I got problems with the libdevmapper version, so I'm now
## using horrible hacks to get it to work.

rootfs_base=/mnt/stateful_partition/rootfss

[ $# -eq 1 ] || {
	echo "Usage: $(basename $0) <container name>" 1>&2
	exit 2
}

name=$1
rootfs=$rootfs_base/$name
run=/usr/local/tmp/docker

[ -f /etc/init/crouton.conf -a `whoami` = root ] || {
	echo "$0: must be run as root from Chrome OS"
	exit 2
}

egrep -q '^docker:' /etc/group || {
	echo "$0: group docker not found, add something like 'docker:x:996:chronos' to /etc/group - as GID use same as docker group in the container"
	exit 2
}
pgrep -x docker > /dev/null && {
	echo "$0: docker is already running"
	exit 1
}
[ -d /sys/fs/cgroup/cpuset ] || {
	mkdir -p /sys/fs/cgroup/cpuset
	mount -t cgroup none /sys/fs/cgroup/cpuset -o cpuset
}

rm -rf $run/../docker
mkdir -p $run

cp -fv $rootfs/usr/lib/libdevmapper.so.1.02 /lib64/libdevmapper.so.9.99
cp -fv $rootfs/usr/bin/docker $run/docker.999
sed -i 's/libdevmapper.so.1.02/libdevmapper.so.9.99/g' /usr/local/tmp/docker.999
$run/docker.999 daemon -D -H unix:///tmp/docker.sock "$@" 2> $rootfs/var/log/docker.log
