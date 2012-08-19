#!/bin/sh

get_sabnzbd_apikey() {
	sab_api_key=`grep -m 1 api_key ${sab_config} | cut -d ' ' -f 3`;
	echo $sab_api_key
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

	cat <<EOF >> ${sab_config}
[categories]
[[tv]]
priority = -100
pp = \"\"
name = tv
script = sabToSickBeard.py
newzbin = \"\"
dir = \"${sab_complete_dir_tv}\"
[[films]]
priority = -100
pp = \"\"
name = films
script = Default
newzbin = \"\"
dir = \"${sab_complete_dir_films}\"
[[music]]
priority = -100
pp = \"\"
name = music
script = Default
newzbin = \"\"
dir = \"${sab_complete_dir_music}\"
EOF

	# echo Starting SABnzbd
	/etc/init.d/sabnzbd start

	# get the API key for SABnzbd
	get_sabnzbd_apikey
	echo Found SABnzbd API key ${sab_api_key}

	wgetopts="-q --delete-after --retry-connrefused --wait=1 --tries=10"

	echo Disabling auto browser
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=misc\&keyword=auto_browser\&value=0\&apikey=${sab_api_key}

	echo Setting download_dir, complete_dir and script_dir
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=misc\&keyword=download_dir\&value=${sab_download_dir}\&apikey=${sab_api_key}
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=misc\&keyword=complete_dir\&value=${sab_complete_dir}\&apikey=${sab_api_key}
	wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=misc\&keyword=script_dir\&value=${sab_script_dir}\&apikey=${sab_api_key}

	if [ "${web_username}" != "{USERNAME}"]; then
		echo Setting web UI username and password
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=misc\&keyword=username\&value=${web_username}\&apikey=${sab_api_key}
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=misc\&keyword=password\&value=${web_password}\&apikey=${sab_api_key}
	fi

	if [ "${nzbmatrix_username}" != "{USERNAME}"]; then
		echo Setting NZBMatrix username and password
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=nzbmatrix\&keyword=username\&value=${nzbmatrix_username}\&apikey=${sab_api_key}
		wget ${wgetopts} http://${ip}:${sab_port}/api\?mode=SetConfig\&section=nzbmatrix\&keyword=apikey\&value=${nzbmatrix_api}\&apikey=${sab_api_key}
	fi
}