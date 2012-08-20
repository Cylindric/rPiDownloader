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
	git clone git://github.com/rembo10/headphones.git
	mv headphones ${headphones_installpath}
	chown -R ${headphones_username}:${usergroup} ${headphones_installpath}
	mkdir -p ${headphones_datapath}
	chown ${headphones_username}:${usergroup} ${headphones_datapath}

	echo "Creating Headphones init script"
	cat <<EOF > /etc/init.d/headphones
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Headphones
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start Headphones at boot time
# Description:       Start Headphones.
### END INIT INFO

case "\$1" in
	start)
		echo "Starting Headphones"
		start-stop-daemon \
			-d ${headphones_installpath} \
			-c ${headphones_username} \
			--start \
			--background \
			--pidfile /var/run/headphones.pid  \
			--make-pidfile \
			--exec /usr/bin/python \
			-- Headphones.py -q --config ${headphones_config} --datadir ${headphones_datapath}
	;;
	stop)
		echo "Stopping Headphones."
		start-stop-daemon --stop --pidfile /var/run/headphones.pid
	;;
	restart)
		echo "Restarting Headphones"
		start-stop-daemon --stop --pidfile /var/run/headphones.pid
		sleep 15
		start-stop-daemon \
			-d ${headphones_installpath} \
			-c ${headphones_username} \
			--start \
			--background \
			--pidfile /var/run/headphones.pid  \
			--make-pidfile \
			--exec /usr/bin/python \
			-- Headphones.py -q --config ${headphones_config} --datadir ${headphones_datapath}
	;;
	*)
		echo "Usage: \$0 {start|stop|restart}"
		exit 1
	esac
EOF
	chmod 755 /etc/init.d/headphones
	update-rc.d headphones defaults

	echo "Starting and stopping once to create required config files"
	/etc/init.d/headphones start
	sleep 15
	/etc/init.d/headphones stop
}



do_headphones_setup() {
	echo "Configuring Headphones"

	echo "Disabling auto-browser launch"
	SetConfig $headphones_config 'General' 'launch_browser' 0

	echo "Setting web ui preferences"
	SetConfig $headphones_config 'General' 'http_port' ${headphones_port}
	SetConfig $headphones_config 'General' 'http_username' "${web_username}"
	SetConfig $headphones_config 'General' 'http_password' "${web_password}"

	echo "Adding API configuration"
	headphones_api_key=`< /dev/urandom tr -dc a-z0-9 | head -c\${1:-32};echo;`
	SetConfig $headphones_config 'General' 'api_enabled' 1
	SetConfig $headphones_config 'General' 'api_key' "${headphones_api_key}"

	get_sabnzbd_apikey
	SetConfig $headphones_config 'SABnzbd' 'enabled' '1'
	SetConfig $headphones_config 'SABnzbd' 'sab_host' "localhost:${sab_port}" 
	SetConfig $headphones_config 'SABnzbd' 'sab_apikey' "${sab_api_key}"
	SetConfig $headphones_config 'SABnzbd' 'sab_category' 'music'

	if [ ${nzbmatrix_enable} -eq 1 ]; then
		echo "Setting nzbmatrix preferences"
		SetConfig $headphones_config 'nzbmatrix' 'nzbmatrix' '1'
		SetConfig $headphones_config 'nzbmatrix' 'nzbmatrix_username' "${nzbmatrix_username}"
		SetConfig $headphones_config 'nzbmatrix' 'nzbmatrix_apikey' "${nzbmatrix_api}"
	fi
}