#!/bin/sh

get_couch_apikey() {
	couch_api_key=`grep -m 1 api_key ${couch_config} | cut -d ' ' -f 3`;
}


do_couchpotato_install() {
	##############################
	#### Couch Potato Install ####
    ##############################
	useradd --system --user-group --no-create-home --groups ${usergroup} ${couch_username}
	git clone git://github.com/RuudBurger/CouchPotatoServer.git
	mv CouchPotatoServer ${couch_installpath}
	chown -R ${couch_username}:${usergroup} ${couch_installpath}
	mkdir -p ${couch_datapath}
	chown ${couch_username}:${usergroup} ${couch_datapath}

	cat <<EOF > /etc/init.d/couchpotato
#!/bin/sh
### BEGIN INIT INFO
# Provides:          CouchPotato
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start CouchPotato at boot time
# Description:       Start CouchPotato.
### END INIT INFO

case "\$1" in
	start)
		echo "Starting CouchPotato."
		mount -a
		sudo -u ${couch_username} -H ${couch_installpath}/CouchPotato.py --daemon --data_dir ${couch_datapath} --config_file ${couch_config}
	;;
	stop)
		echo "Stopping CouchPotato."
		p=\`ps aux | grep -v grep | grep CouchPotato.py | tr -s \ | cut -d ' ' -f 2\`
		if [ -n "\$p" ]; then
			couch_api_key=\`grep -m 1 api_key ${couch_config} | cut -d ' ' -f 3\`;
			couch_port=\`grep -m 1 port ${couch_config} | cut -d ' ' -f 3\`;
			wget -q --delete-after http://localhost:\${couch_port}/api/\${couch_api_key}/app.shutdown
			while ps -p \$p > /dev/null; do sleep 1; done
		fi
	;;
	*)
		echo "Usage: \$0 {start|stop}"
		exit 1
	;;
esac
EOF

	chmod 755 /etc/init.d/couchpotato
	update-rc.d couchpotato defaults
	
	# start and stop once to create required config files
	/etc/init.d/couchpotato start
	sleep 30
	/etc/init.d/couchpotato stop
}



do_couchpotato_setup() {
	echo "Configuring Couch Potato"

	echo "Disabling auto-browser launch"
	SetConfig $couch_config 'core' 'launch_browser' 0

	echo "Setting web ui preferences"
	md5pass=`echo -n "${web_password}" | md5sum - | cut -f1 -d" "`
	SetConfig $couch_config 'core' 'port' ${couch_port}
	if [ $web_protect -eq 1 ]; then
		SetConfig $couch_config 'core' 'username' "${web_username}"
		SetConfig $couch_config 'core' 'password' "${md5pass}"
	fi
	SetConfig $couch_config 'core' 'show_wizard' '0'
	SetConfig $couch_config 'core' 'permission_folder' '0775'
	SetConfig $couch_config 'core' 'permission_file' '0775'

	echo "Setting download preferences"	
	SetConfig $couch_config 'renamer' 'enabled' '1'
	SetConfig $couch_config 'renamer' 'from' "${sab_complete_dir_films}"
	SetConfig $couch_config 'renamer' 'to' "${film_root}"
	SetConfig $couch_config 'renamer' 'cleanup' '1'

	echo "Setting SABnzbd integration preferences"
	get_sabnzbd_apikey
	SetConfig $couch_config 'sabnzbd' 'enabled' '1'
	SetConfig $couch_config 'sabnzbd' 'host' "localhost:${sab_port}" 
	SetConfig $couch_config 'sabnzbd' 'api_key' "${sab_api_key}"
	SetConfig $couch_config 'sabnzbd' 'category' 'films'

	if [ ${nzbmatrix_enable} -eq 1 ]; then
		echo "Setting nzbmatrix preferences"
		SetConfig $couch_config 'nzbmatrix' 'enabled' '1'
		SetConfig $couch_config 'nzbmatrix' 'username' "$nzbmatrix_username"
		SetConfig $couch_config 'nzbmatrix' 'api_key' "$nzbmatrix_api"
	fi

	if [ $xbmc_enable -eq 1 ]; then
		echo "Setting xbmc preferences"
		SetConfig $couch_config 'xbmc' 'enabled' '1'
		SetConfig $couch_config 'xbmc' 'username' "$xbmc_username"
		SetConfig $couch_config 'xbmc' 'password' "$xbmc_password"
		SetConfig $couch_config 'xbmc' 'host' "$xbmc_host"
	fi

	/etc/init.d/couchpotato start
}