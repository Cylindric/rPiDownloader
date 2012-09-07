#!/bin/sh

get_headphones_apikey() {
	headphones_api_key=`grep -m 1 api_key ${headphones_config} | cut -d ' ' -f 3`;
}

do_headphones_install() {
	######################
	# Headphones Install #
    ######################
    echo "Adding new user for Headphones"
	useradd --system --user-group --no-create-home --groups ${usergroup} ${headphones_username}

	echo "Downloading Headphones"
	git clone https://github.com/rembo10/headphones.git
	mv headphones ${headphones_installpath}
	chown -R ${headphones_username}:${usergroup} ${headphones_installpath}
	chmod u+x ${headphones_installpath}/Headphones.py
	mkdir -p ${headphones_datapath}
	cp `dirname "$0"`/headphones.ini /var/headphones/
	chown ${headphones_username}:${usergroup} ${headphones_datapath}

	echo "Creating Headphones init script"
	cat <<EOF > /etc/init.d/headphones
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Headphones
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start Headphones at boot time
# Description:       Start Headphones.
### END INIT INFO

case "\$1" in
	start)
		echo "Starting Headphones"
		mount -a
		/usr/bin/sudo -u ${headphones_username} -H ${headphones_installpath}/Headphones.py -d --config ${headphones_config}
	;;
	stop)
		echo "Stopping Headphones."
		p=\`ps aux | grep -v grep | grep Headphones.py | tr -s \ | cut -d ' ' -f 2\`
		if [ -n "\$p" ]; then
			headphones_api_key=\`grep -m 1 api_key ${headphones_config} | cut -d ' ' -f 3\`;
			headphones_port=\`grep -m 1 port ${headphones_config} | cut -d ' ' -f 3\`;
			wget -q --delete-after http://localhost:\${headphones_port}/api/\${headphones_api_key}/app.shutdown
			while ps -p \$p > /dev/null; do sleep 1; done
		fi
	;;
	*)
		echo "Usage: \$0 {start|stop}"
		exit 1
	;;
	esac
EOF
	chmod 755 /etc/init.d/headphones
	update-rc.d headphones defaults
}



do_headphones_setup() {
	echo "Configuring Headphones"

	if [ $headphones_clobber_useragent -eq 1 ]; then
		echo "Chaning User-Agent string"
		useragent="python-rPiDownloader/$version ($contact)"
		useragent=`echo "${useragent}" | sed -e 's/[\\/&]/\\\\&/g'`
		sed -i "s/_useragent = \".*/_useragent = \"$useragent\"/g"  ${headphones_installpath}/lib/musicbrainzngs/musicbrainz.py
	fi

	echo "Disabling auto-browser launch"
	SetConfig $headphones_config 'General' 'launch_browser' 0

	echo "Setting web ui preferences"
	SetConfig $headphones_config 'General' 'http_port' ${headphones_port}
	if [ $web_protect -eq 1 ]; then
		SetConfig $headphones_config 'General' 'http_username' "${web_username}"
		SetConfig $headphones_config 'General' 'http_password' "${web_password}"
	fi
	SetConfig $headphones_config 'General' 'log_dir' "${headphones_datapath}/logs"

	echo "Adding API configuration"
	headphones_api_key=`< /dev/urandom tr -dc a-z0-9 | head -c\${1:-32};echo;`
	SetConfig $headphones_config 'General' 'api_enabled' '1'
	SetConfig $headphones_config 'General' 'api_key' "${headphones_api_key}"

	get_sabnzbd_apikey
	SetConfig $headphones_config 'SABnzbd' 'enabled' '1'
	SetConfig $headphones_config 'SABnzbd' 'sab_host' "localhost:${sab_port}" 
	SetConfig $headphones_config 'SABnzbd' 'sab_apikey' "${sab_api_key}"
	SetConfig $headphones_config 'SABnzbd' 'sab_category' 'music'

	SetConfig $headphones_config 'General' 'download_dir' "${sab_complete_dir_music}"
	SetConfig $headphones_config 'General' 'destination_dir' "${music_root}"
	SetConfig $headphones_config 'General' 'music_dir' "${music_root}"
	SetConfig $headphones_config 'General' 'move_files' '1'
	SetConfig $headphones_config 'General' 'rename_files' '1'
	SetConfig $headphones_config 'General' 'cleanup_files' '1'
	SetConfig $headphones_config 'General' 'add_album_art' '1'
	SetConfig $headphones_config 'General' 'lossless_destination_dir' '""'

	if [ ${nzbmatrix_enable} -eq 1 ]; then
		echo "Setting nzbmatrix preferences"
		SetConfig $headphones_config 'NZBMatrix' 'nzbmatrix' '1'
		SetConfig $headphones_config 'NZBMatrix' 'nzbmatrix_username' "${nzbmatrix_username}"
		SetConfig $headphones_config 'NZBMatrix' 'nzbmatrix_apikey' "${nzbmatrix_api}"
	fi

	if [ $xbmc_enable -eq 1 ]; then
		echo "Setting xbmc preferences"
		SetConfig $headphones_config 'XBMC' 'xbmc_enabled' '1'
		SetConfig $headphones_config 'XBMC' 'xbmc_host' "http://${xbmc_host}:${xbmc_port}"
		SetConfig $headphones_config 'XBMC' 'xbmc_username' = "${xbmc_username}"
		SetConfig $headphones_config 'XBMC' 'xbmc_password' = "${xbmc_password}"
		SetConfig $headphones_config 'XBMC' 'xbmc_update' '1'
		SetConfig $headphones_config 'XBMC' 'xbmc_notify' '1'
	fi

	/etc/init.d/headphones start

}