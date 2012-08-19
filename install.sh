#!/bin/sh
. ./install.conf

. ./raspberrypi.sh
. ./sabnzbd.sh
. ./sickbeard.sh
. ./couchpotato.sh
. ./headphones.sh


ip=`ifconfig eth0 | grep "inet addr" | awk -F: '{print \$2}' | awk '{print \$1}'`;
sab_api_key=unknown


# Stages are
# 1 Expand RootFS
# 2 Core Setup (default)
# 3 Package installation
# 4 Package setup
start_stage=2
while getopts "s:" opt; do
	case $opt in
		s)
			start_stage=$OPTARG
			echo "Start stage set to $start_stage"
			;;
		\?)
			echo "invalid option"
			exit 1
			;;
		esac
done


# Configuration checks
config_ok=1
if [ "${pi_password}" = '{PASSWORD}' ]; then
	echo "pi_password not set."
	config_ok=0
fi
if [ "${web_username}" = '{USERNAME}' ]; then
	echo "web_username not set."
	config_ok=0
fi
if [ "${web_password}" = '{PASSWORD}' ]; then
	echo "web_password not set."
	config_ok=0
fi
if [ $config_ok -eq 0 ]; then
	echo "Some options are missing or incorrect. Edit install.conf and set a web password."
	exit 0
fi



SetConfig() {
	if [ $# -eq 3 ]; then
		config_file=$1
		config_key=$2
		config_value=$3
		config_value=`echo "${config_value}" | sed -e 's/[\\/&]/\\\\&/g'`
		sed -i "s/$config_key =.*/$config_key = $config_value/" $config_file
	else
		config_file=$1
		section_name=$2
		config_key=$3
		config_value=$4
		config_value=`echo "${config_value}" | sed -e 's/[\\/&]/\\\\&/g'`
		sed -i "/\[$section_name\]/,/\[/s/$config_key =.*/$config_key = $config_value/" $config_file
	fi

}





do_pre_install() {
	# Install Packages
	echo "deb-src http://mirrordirector.raspbian.org/raspbian/ wheezy main contrib non-free rpi" >> /etc/apt/sources.list
	apt-get -q update
	apt-get -qqy install python2.6 python-cheetah python-openssl par2
	apt-get -qqy build-dep unrar-nonfree
	apt-get -qqy source -b unrar-nonfree
	dpkg -i unrar*.deb
	rm -rf unrar*

	# Remove unwanted packages
	if [ $purge_x -eq 1 ]; then
		echo "Removing unwanted packages"
		apt-get -qqy purge scratch xserver-common lxde-common lxinput lxappearance lxpanel lxpolkit lxrandr lxsession-edit lxshortcut lxtask lxterminal gnome-icon-theme gnome-themes-standard
		rm -r /usr/lib/xorg/modules/linux /usr/lib/xorg/modules/extensions /usr/lib/xorg/modules /usr/lib/xorg
		apt-get -qqy autoremove
		apt-get -qqy autoclean
	fi
	apt-get -qqy clean

	# Add users and groups
	addgroup ${usergroup}
	usermod -a -G ${usergroup} pi
}









do_media_setup() {
	mkdir -p ${media_root}/films
	mkdir -p ${media_root}/music
	mkdir -p ${media_root}/tv
	mkdir -p ${sab_download_dir}
	mkdir -p ${sab_complete_dir}
	mkdir -p ${sab_complete_dir_music}
	mkdir -p ${sab_complete_dir_films}
	mkdir -p ${sab_complete_dir_tv}
	mkdir -p ${media_root}/incoming/sickbeard
	mkdir -p ${media_root}/incoming/couchpotato

	chown -R root:${usergroup} ${media_root}
	chmod -R 775 ${media_root}
}




cd /tmp
if [ $start_stage -leq 1 ]; then
	do_rpi_expand_rootfs
fi

if [ $start_stage -leq 2 ]; then
	do_rpi_setup
	do_pre_install
fi

if [ $start_stage -leq 3 ]; then
	do_sabnzbd_install
	do_sickbeard_install
	do_couchpotato_install
	do_headphones_install
fi

if [ $start_stage -leq 4 ]; then
	do_media_setup
	do_sabnzbd_setup
	do_sickbeard_setup
	do_couchpotato_setup
fi
