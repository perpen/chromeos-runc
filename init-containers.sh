#!/bin/bash -e
## To be run on ChromeOS boot from /etc/init/containers.conf.
## Prepare a few things (bind-mounts, optionally docker) then starts containers.
## Usage: $0 [docker] [vbox]

rootfs_base=/mnt/stateful_partition/chroots
base=$(dirname $0)

## Loads vbox modules from the specified rootfs.
setup_vbox() {
	local source_container=$1
	local dir=$rootfs_base/$source_container/usr/lib/modules/3.14.0/kernel/misc

	[ -d $dir ] || {
		echo "$0: invalid virtualbox modules directory: $dir" 1>&2
		return 1
	}

	cd $dir
	for i in *.ko; do
		insmod $i
	done
}

setup_docker() {
	$base/docker-daemon.sh
}

start_container() {
	local name=$1
	local rootfs=$rootfs_base/$name

	## Reuse host tmpfs.
	## Plus it's required to talk to access /tmp/docker.sock from the 
	## container.
	mount --bind /tmp $rootfs/tmp

	## If crouton is installed in the container, prepare xiwi shared memory hack.
	[ -f $rootfs/usr/local/bin/croutonversion ] && {
		mount --bind /proc $rootfs/var/host/proc
		mount --bind /dev $rootfs/var/host/dev
		mount --bind /run/dbus $rootfs/var/host/dbus
	}

	$base/start-container.sh arch \
		< /dev/null > /tmp/container-$name.out 2>&1 &
}

mount -o remount,suid,exec /mnt/stateful_partition
for opt in "$@"; do
	eval setup_$opt
done
start_container arch
