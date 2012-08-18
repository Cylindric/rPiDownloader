#!/bin/sh
. ./install.conf


ip=`ifconfig eth0 | grep "inet addr" | awk -F: '{print \$2}' | awk '{print \$1}'`;
sab_api_key=unknown


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



get_sabnzbd_apikey()
{
	sab_api_key=`grep -m 1 api_key ${sab_config} | cut -d ' ' -f 3`;
	echo ${sab_api_key}	
}

get_sickbeard_apikey()
{
	sb_api_key=`grep -m 1 api_key ${sb_config} | cut -d ' ' -f 3`;
	echo ${sb_api_key}	
}



do_expand_rootfs() {
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



do_setup() {
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
	apt-get update
	if [ $do_os_update -eq 1 ]; then
		apt-get -y -o Dpkg::Options::="--force-confnew" upgrade
	fi
	if [ $do_firmware_update -eq 1 ]; then
		apt-get -y install git
		git clone git://github.com/Hexxeh/rpi-update.git
		./rpi-update/rpi-update
		rm -rf ./rpi-update
	fi
}



do_pre_install() {
	# Install Packages
	echo "deb-src http://mirrordirector.raspbian.org/raspbian/ wheezy main contrib non-free rpi" >> /etc/apt/sources.list
	apt-get update
	apt-get -y install python2.6 python-cheetah python-openssl par2
	apt-get -y build-dep unrar-nonfree
	apt-get source -b unrar-nonfree
	dpkg -i unrar*.deb
	rm -rf unrar*

	# Remove unwanted packages
	if [ $purge_x -eq 1 ]; then
		apt-get -y purge scratch xserver-common lxde-common lxinput lxappearance lxpanel lxpolkit lxrandr lxsession-edit lxshortcut lxtask lxterminal gnome-icon-theme gnome-themes-standard
		rm -r /usr/lib/xorg/modules/linux /usr/lib/xorg/modules/extensions /usr/lib/xorg/modules /usr/lib/xorg
		apt-get -y autoremove
		apt-get -y autoclean
	fi
	apt-get -y clean

	# Add users and groups
	addgroup ${usergroup}
	usermod -a -G ${usergroup} pi
}


do_sabnzbd_install() {
	###################
	# SABnsbd Install #
    ###################
    echo "Adding new user for SABnzbd"
	useradd --system --user-group --no-create-home --groups ${usergroup} ${sab_username}

	echo "Downloading SABnzbd"
	wget -q http://downloads.sourceforge.net/project/sabnzbdplus/sabnzbdplus/0.7.3/SABnzbd-0.7.3-src.tar.gz

	echo "Extracting SABnzbd"
	tar xzf SABnzbd-0.7.3-src.tar.gz
	mv SABnzbd-0.7.3 ${sab_installpath}
	chown -R ${sab_username}:${usergroup} ${sab_installpath}

	echo "Creating SABnzbd data directories"
	mkdir -p ${sab_datapath}
	chown ${sab_username}:${usergroup} ${sab_datapath}

	echo "Creating SABnzbd init script"
	cat <<EOF > /etc/init.d/sabnzbd
#!/bin/sh
### BEGIN INIT INFO
# Provides:          SABnzbd
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start SABnzbd at boot time
# Description:       Start SABnzbd.
### END INIT INFO

case "\$1" in
	start)
		echo "Starting SABnzbd"
		/usr/bin/sudo -u ${sab_username} -H ${sab_installpath}/SABnzbd.py -d -f ${sab_config}
	;;
	stop)
		echo "Stopping SABnzbd."
		p=\`ps aux | grep -v grep | grep SABnzbd.py | tr -s \ | cut -d ' ' -f 2\`
		if [ -n "\$p" ]; then
			kill -2 \$p > /dev/null
			while ps -p \$p > /dev/null; do sleep 1; done
		fi
	;;
	*)
		echo "Usage: \$0 {start|stop}"
		exit 1
	esac
EOF
	chmod 755 /etc/init.d/sabnzbd
	update-rc.d sabnzbd defaults

	echo "Removing SABnzbd installation files"
	rm SABnzbd*.tar.gz

	echo "Starting and stopping once to create required config files"
	/etc/init.d/sabnzbd start
	/etc/init.d/sabnzbd stop
}


do_sickbeard_install() {
	############################
	#### Sick Beard Install ####
    ############################
	useradd --system --user-group --no-create-home --groups ${usergroup} ${sb_username}
	git clone git://github.com/midgetspy/Sick-Beard.git
	mv Sick-Beard ${sb_installpath}
	chown -R ${sb_username}:${usergroup} ${sb_installpath}
	chmod ug+rw ${sb_installpath}/autoProcessTV/
	mkdir -p ${sb_datapath}
	chown ${sb_username}:${usergroup} ${sb_datapath}

	cat <<EOF > /etc/init.d/sickbeard
#!/bin/sh
### BEGIN INIT INFO
# Provides:          SickBeard
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start SickBeard at boot time
# Description:       Start SickBeard.
### END INIT INFO

case "\$1" in
	start)
		echo "Starting SickBeard."
		sudo -u ${sb_username} -H ${sb_installpath}/SickBeard.py -d --datadir ${sb_datapath} --config ${sb_config}
	;;
	stop)
		echo "Stopping SickBeard."
		p=\`ps aux | grep -v grep | grep SickBeard.py | tr -s \ | cut -d ' ' -f 2\`
		if [ -n "\$p" ]; then
			sb_api_key=\`grep -m 1 api_key ${sb_config} | cut -d ' ' -f 3\`;
			sb_port=\`grep -m 1 web_port ${sb_config} | cut -d ' ' -f 3\`;
			wget -q --delete-after http://localhost:\${sb_port}/api/\${sb_api_key}/\?cmd=sb.shutdown
			while ps -p \$p > /dev/null; do sleep 1; done
		fi
	;;
	*)
		echo "Usage: \$0 {start|stop}"
		exit 1
esac
EOF

	chmod 755 /etc/init.d/sickbeard
	update-rc.d sickbeard defaults

	# start and stop once to create required config files
	# We have to just kill the process for now, because we don't have the API enabled yet
	/etc/init.d/sickbeard start
	p=\`ps aux | grep -v grep | grep SickBeard.py | tr -s \ | cut -d ' ' -f 2\`
	kill -9 $p
}


do_couchpotato_install() {
	##############################
	#### Couch Potato Install ####
    ##############################
	useradd --system --user-group --no-create-home --groups ${usergroup} ${couch_username}
	git clone git://github.com/RuudBurger/CouchPotato.git
	mv CouchPotato ${couch_installpath}
	chown -R ${couch_username}:${usergroup} ${couch_installpath}
	mkdir -p ${couch_datapath}
	chown ${couch_username}:${usergroup} ${couch_datapath}

	cat <<EOF > /etc/init.d/couchpotato
#!/bin/sh
### BEGIN INIT INFO
# Provides:          CouchPotato
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start CouchPotato at boot time
# Description:       Start CouchPotato.
### END INIT INFO

case "\$1" in
	start)
		echo "Starting CouchPotato."
		sudo -u ${couch_username} -H ${couch_installpath}/CouchPotato.py -d --datadir ${couch_datapath} --config ${couch_config}
	;;
	stop)
		echo "Stopping CouchPotato."
		p=\`ps aux | grep -v grep | grep CouchPotato.py | tr -s \ | cut -d ' ' -f 2\`
		if [ -n "\$p" ]; then
			kill -2 \$p > /dev/null
			while ps -p \$p > /dev/null; do sleep 1; done
		fi
	;;
	*)
		echo "Usage: \$0 {start|stop}"
		exit 1
esac
EOF

	chmod 755 /etc/init.d/couchpotato
	update-rc.d couchpotato defaults
	
	# start and stop once to create required config files
	/etc/init.d/couchpotato start
	/etc/init.d/couchpotato stop
}


do_media_setup() {
	mkdir -p ${media_root}/films
	mkdir -p ${media_root}/tv
	mkdir -p ${media_root}/incoming/sabnzbd/incomplete
	mkdir -p ${media_root}/incoming/sabnzbd/complete
	mkdir -p ${media_root}/incoming/sickbeard
	mkdir -p ${media_root}/incoming/couchpotato

	chown -R root:${usergroup} ${media_root}
	chmod -R 775 ${media_root}
}


do_sabnzbd_setup() {
	echo Making sure SABnzbd is running, to create inital files and default config...
	/etc/init.d/sabnzbd start

	echo Shutting down to add non-api settings
	/etc/init.d/sabnzbd stop

	if [ "${nntp_server}" != "{SERVER_ADDRESS}"]; then
		cat <<EOF >> /var/sabnzbd/sabnzbd.ini
[servers]
[[${nntp_server}]]
username = ${nntp_username}
enable = 1
name = ${nntp_server}
fillserver = 0
connections = ${nntp_connections}
ssl = ${nntp_ssl}
host = ${nntp_server}
timeout = 120
password = ${nntp_password}
optional = 0
port = ${nntp_port}
retention = 0
EOF
	fi

	cat <<EOF >> /var/sabnzbd/sabnzbd.ini
[categories]
[[tv]]
priority = -100
pp = \"\"
name = tv
script = sabToSickBeard.py
newzbin = \"\"
dir = \"\"
[[films]]
priority = -100
pp = \"\"
name = films
script = Default
newzbin = \"\"
dir = \"\"
EOF

	# echo Starting SABnzbd
	/etc/init.d/sabnzbd start

	# get the API key for SABnzbd
	get_sabnzbd_apikey
	echo Found SABnzbd API key ${sab_api_key}

	wgetopts="-q --delete-after --retry-connrefused --wait=1 --tries=10"

	echo Disabling auto browser
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=misc\&keyword=auto_browser\&value=0\&apikey=${sab_api_key}

	echo Setting download_dir, complete_dir and script_dir
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=misc\&keyword=download_dir\&value=${sab_download_dir}\&apikey=${sab_api_key}
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=misc\&keyword=complete_dir\&value=${sab_complete_dir}\&apikey=${sab_api_key}
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=misc\&keyword=script_dir\&value=${sab_script_dir}\&apikey=${sab_api_key}

	if [ "${web_username}" != "{USERNAME}"]; then
		echo Setting web UI username and password
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=misc\&keyword=username\&value=${web_username}\&apikey=${sab_api_key}
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=misc\&keyword=password\&value=${web_password}\&apikey=${sab_api_key}
	fi

	if [ "${nzbmatrix_username}" != "{USERNAME}"]; then
		echo Setting NZBMatrix username and password
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=nzbmatrix\&keyword=username\&value=${nzbmatrix_username}\&apikey=${sab_api_key}
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=set_config\&section=nzbmatrix\&keyword=apikey\&value=${nzbmatrix_api}\&apikey=${sab_api_key}
	fi
}


do_sickbeard_setup() {
	# ensure the API is enabled
	echo "Adding API configuration to Sickbeard"
	sb_api_key=`< /dev/urandom tr -dc a-z0-9 | head -c\${1:-32};echo;`
	sed -i '/\[General\]/,/\[/s/web_username =.*/web_username = 1/' ${sb_config}
	sed -i '/\[General\]/,/\[/s/api_key =.*/api_key = ${sb_api_key}/' ${sb_config}

	echo "Setting web ui preferences"
	sed -i '/\[General\]/,/\[/s/web_username =.*/web_username = ${web_username}/' ${sb_config}
	sed -i '/\[General\]/,/\[/s/web_password =.*/web_password = ${web_password}/' ${sb_config}

	echo "Setting SABnzbd integration preferences"
	sed -i '/\[General\]/,/\[/s/move_associated_files =.*/move_associated_files = 1/' ${sb_config}
	sed -i '/\[General\]/,/\[/s/keep_processed_dir =.*/keep_processed_dir = 0/' ${sb_config}
	sed -i '/\[General\]/,/\[/s/nzb_method =.*/nzb_method = sabnzbd/' ${sb_config}
	sed -i '/\[SABnzbd\]/,/\[/s/sab_host =.*/host = ${ip}:${sab_port}/' ${sb_config}
	sed -i '/\[SABnzbd\]/,/\[/s/sab_apikey =.*/apikey = ${sab_api_key}/' ${sb_config}
	sed -i '/\[SABnzbd\]/,/\[/s/sab_category =.*/category = tv/' ${sb_config}

	echo "Setting NZBMatrix integration preferences"
	sed -i '/\[NZBMatrix\]/,/\[/s/nzbmatrix =.*/nzbmatrix = 1/' ${sb_config}
	sed -i '/\[NZBMatrix\]/,/\[/s/nzbmatrix_username =.*/nzbmatrix_username = ${nzbmatrix_username}/' ${sb_config}
	sed -i '/\[NZBMatrix\]/,/\[/s/nzbmatrix_apikey =.*/nzbmatrix_apikey = ${nzbmatrix_api}/' ${sb_config}

	echo "Setting XBMC integration preferences"
	sed -i '/\[General\]/,/\[/s/use_banner =.*/use_banner = 1/' ${sb_config}
	sed -i '/\[General\]/,/\[/s/metadata_xbmc =.*/metadata_xbmc = 1\|1\|1\|1\|1\|1/' ${sb_config}

}


do_couchpotato_setup() {
	echo "Configuring Couch Potato"

	echo "Disabling auto-browser launch"
	sed -i "/\[global\]/,/\[/s/launchbrowser =.*/launchbrowser = False/" ${couch_config}

	echo "Setting web ui preferences"
	sed -i "/\[global\]/,/\[/s/port =.*/port = ${couch_port}/" ${couch_config}
	sed -i "/\[global\]/,/\[/s/username =.*/username = ${web_username}/" ${couch_config}
	sed -i "/\[global\]/,/\[/s/password =.*/password = ${web_password}/" ${couch_config}

	echo "Setting download preferences"
	replace=` echo "${media_root}" | sed -e 's/[\\/&]/\\\\&/g'`
	sed -i "/\[Renamer\]/,/\[/s/enabled =.*/enabled = True/" ${couch_config}
	sed -i "/\[Renamer\]/,/\[/s/download =.*/download = ${replace}\/sabnzbd\/complete\//" ${couch_config}
	sed -i "/\[Renamer\]/,/\[/s/destination =.*/destination = ${replace}\/films\//" ${couch_config}
	sed -i "/\[Renamer\]/,/\[/s/cleanup =.*/cleanup = True/" ${couch_config}

	echo "Setting SABnzbd integration preferences"
	get_sabnzbd_apikey
	sed -i "/\[Sabnzbd\]/,/\[/s/host =.*/host = localhost:${sab_port}/" ${couch_config}
	sed -i "/\[Sabnzbd\]/,/\[/s/apikey =.*/apikey = ${sab_api_key}/" ${couch_config}
	sed -i "/\[Sabnzbd\]/,/\[/s/username =.*/username = ${web_username}/" ${couch_config}
	sed -i "/\[Sabnzbd\]/,/\[/s/password =.*/password = ${web_password}/" ${couch_config}
	sed -i "/\[Sabnzbd\]/,/\[/s/category =.*/category = films/" ${couch_config}

	if [ "${nzbmatrix_enable}" -eq 1 ]; then
		echo "Setting nzbmatrix preferences"
		sed -i "/\[NZBMatrix\]/,/\[/s/enabled =.*/enabled = True/" ${couch_config}
		sed -i "/\[NZBMatrix\]/,/\[/s/username =.*/username = ${nzbmatrix_username}/" ${couch_config}
		sed -i "/\[NZBMatrix\]/,/\[/s/apikey =.*/apikey = ${nzbmatrix_api}/" ${couch_config}
	fi
}



cd /tmp
if [ $expand_rootfs -eq 1 ]; then
	do_expand_rootfs
fi



#do_setup
#do_pre_install

#do_sabnzbd_install
#do_sickbeard_install
#do_couchpotato_install

#do_media_setup
#do_sabnzbd_setup
#do_sickbeard_setup
#do_couchpotato_setup

#sync
#reboot