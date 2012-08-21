#!/bin/sh

get_sickbeard_apikey() {
	sb_api_key=`grep -m 1 api_key ${sb_config} | cut -d ' ' -f 3`;
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
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start SickBeard at boot time
# Description:       Start SickBeard.
### END INIT INFO

case "\$1" in
	start)
		echo "Starting SickBeard."
		mount -a
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
	;;
esac
EOF

	chmod 755 /etc/init.d/sickbeard
	update-rc.d sickbeard defaults

	# start and stop once to create required config files
	# We have to just kill the process for now, because we don't have the API enabled yet
	/etc/init.d/sickbeard start
	kill -9 `ps aux | grep -v grep | grep SickBeard.py | tr -s \ | cut -d ' ' -f 2`
}



do_sickbeard_setup() {
	# ensure the API is enabled
	echo "Adding API configuration"
	sb_api_key=`< /dev/urandom tr -dc a-z0-9 | head -c\${1:-32};echo;`
	SetConfig $sickbeard_config 'General' 'api_enabled' 1
	SetConfig $sickbeard_config 'General' 'api_key' "${sb_api_key}"

	if [ $web_protect -eq 1 ]; then
		echo "Setting web ui preferences"
		SetConfig $sickbeard_config 'General' 'web_username' "${web_username}"
		SetConfig $sickbeard_config 'General' 'web_password' "${web_password}"
	fi

	echo "Setting SABnzbd integration preferences"
	SetConfig $sickbeard_config 'General' 'move_associated_files' '1'
	SetConfig $sickbeard_config 'General' 'keep_processed_dir' '0'
	SetConfig $sickbeard_config 'General' 'nzb_method' 'sabnzbd'
	SetConfig $sickbeard_config 'SABnzbd' 'sab_host' "http:\/\/localhost:${sab_port}"
	SetConfig $sickbeard_config 'SABnzbd' 'sab_apikey' "${sab_api_key}"
	SetConfig $sickbeard_config 'SABnzbd' 'sab_category' 'tv'

	if [ ${nzbmatrix_enable} -eq 1 ]; then
		echo "Setting NZBMatrix integration preferences"
		SetConfig $sickbeard_config 'NZBMatrix' 'nzbmatrix' '1'
		SetConfig $sickbeard_config 'NZBMatrix' 'nzbmatrix_username' "${nzbmatrix_username}"
		SetConfig $sickbeard_config 'NZBMatrix' 'nzbmatrix_apikey' "${nzbmatrix_api}"
	fi

	if [ ${nzbmatrix_enable} -eq 1 ]; then
		echo "Setting XBMC integration preferences"
		SetConfig $sickbeard_config 'General' 'use_banner' '1'
		SetConfig $sickbeard_config 'General' 'metadata_xbmc' '1\|1\|1\|1\|1\|1'

		SetConfig $sickbeard_config 'XBMC' 'use_xbmc' '1'
		SetConfig $sickbeard_config 'XBMC' 'xbmc_host' "${xbmc_host}"
		SetConfig $sickbeard_config 'XBMC' 'xbmc_username' "${xbmc_username}"
		SetConfig $sickbeard_config 'XBMC' 'xbmc_password' "${xbmc_password}"
		SetConfig $sickbeard_config 'XBMC' 'xbmc_notify_ondownload' '1'
	fi

	/etc/init.d/sickbeard start
}
