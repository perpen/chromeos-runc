#!/bin/bash -e
## Creates/updates the config.json at top of rootfs from our template,
## then starts a container.
## Usage: $0 <container name>

rootfs_base=/mnt/stateful_partition/chroots

[ $(whoami) = root ] || {
        echo "$0: must be run as root" 1>&2
        exit 2
}

[ $# -eq 1 ] || {
	echo "Usage: $(basename $0) <name>
    Starts container with root in $rootfs_base/<name>" 1>&2
    exit 2
}

name=$1
rootfs="$rootfs_base/$name"
hostname=$name

[ -d $rootfs/etc ] || {
	echo "$0: not a valid chroot: $rootfs"
	exit 1
}

cat $(dirname $0)/config-template.json \
	| sed 's#"hostname" *: *"[^"]*"#"hostname": "'$hostname'"#g' \
	> $rootfs/config.json

rm -rf /run/runc/$name #FIXME
cd $rootfs
$(dirname $0)/runc start $name
