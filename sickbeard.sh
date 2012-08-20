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
	p=`ps aux | grep -v grep | grep SickBeard.py | tr -s \ | cut -d ' ' -f 2`
	kill -9 $p
}



do_sickbeard_setup() {
	# ensure the API is enabled
	echo "Adding API configuration"
	sb_api_key=`< /dev/urandom tr -dc a-z0-9 | head -c\${1:-32};echo;`
	sed -i '/\[General\]/,/\[/s/api_enabled =.*/api_enabled = 1/' ${sb_config}
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
