#!/bin/sh

do_rpi_expand_rootfs() {
  # Get the starting offset of the root partition
  PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^2" | cut -f 2 -d:)
  [ "$PART_START" ] || return 1
  # Return value will likely be error for fdisk as it fails to reload the 
  # partition table because the root fs is mounted
  fdisk /dev/mmcblk0 <<EOF
p
d
2
n
p
2
$PART_START

p
w
EOF

  # now set up an init.d script
cat <<\EOF > /etc/init.d/resize2fs_once &&
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5 S
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "$1" in
  start)
    log_daemon_msg "Starting resize2fs_once" &&
    resize2fs /dev/mmcblk0p2 &&
    rm /etc/init.d/resize2fs_once &&
    update-rc.d resize2fs_once remove &&
    log_end_msg $?
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF
  chmod +x /etc/init.d/resize2fs_once &&
  update-rc.d resize2fs_once defaults
}


do_rpi_setup() {
	# change the password
	echo "pi:${pi_password}" | chpasswd

	# disable the default auto-login
	if [ -e /etc/profile.d/raspi-config.sh ]; then
		rm -f /etc/profile.d/raspi-config.sh
		sed -i /etc/inittab \
			-e "s/^#\(.*\)#\s*RPICFG_TO_ENABLE\s*/\1/" \
			-e "/#\s*RPICFG_TO_DISABLE/d"
		telinit q
	fi

	# prevent booting to desktop
	update-rc.d lightdm disable 2

	# update the rPi core
	apt-get -q update
	if [ $do_os_update -eq 1 ]; then
		apt-get -y -o Dpkg::Options::="--force-confnew" upgrade
	fi
	if [ $do_firmware_update -eq 1 ]; then
		echo "Intalling Git, downloading rpi-update and updating"
		apt-get -qqy install git
		git clone git://github.com/Hexxeh/rpi-update.git
		./rpi-update/rpi-update
		rm -rf ./rpi-update
	fi
}