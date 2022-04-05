#!/usr/bin/env bash
#
# SCRIPT FROM 3CX !
#
SCRIPT=$(/bin/readlink -f $0)
VERSION_BEFORE=`/usr/bin/lsb_release -r | cut -f2`
ARCHITECTURE=`dpkg --print-architecture`
LOG_UPDATE="/tmp/UPDATE.log"
LOG_TCX_BACKUP="/tmp/BACKUP.log"
FLAG_UPDATE_SUCCESS="/tmp/UPDATE_SUCCESSFULL"
FLAG_UPDATE_FAIL="/tmp/UPDATE_FAILED"
FLAG_UPDATE_RUNNING="/tmp/UPDATE_RUNNING"
WORKING_DIRECTORY="/tmp"
WEBAPI_URL="https://webapi.3cx.com/upgrade"
LAST_V16_VERSION="168"
CURRENT_V18_VERSION="1803"
SCRIPT_VERSION="727fdbf46d944ae532b0ac89cc2698800d30d80a3fd87da3726fe47e7759908f"

# IM variables
python_command=python
im_is_enabled=0
im_management=0
im_dataaccess=0

export DEBIAN_FRONTEND=noninteractive
{

function log {
	/bin/echo -e "\e[33m====== [`date +"%H:%M:%S"`] $1: $2\e[39m"
}

function sendStatusAPI {
	/usr/bin/wget --post-file=$LOG_UPDATE $WEBAPI_URL 2> /dev/null > /dev/null
}

function success {
	# Send data
	/bin/cp $LOG_UPDATE $FLAG_UPDATE_SUCCESS
	/bin/rm -f $FLAG_UPDATE_RUNNING
	/bin/echo "::SUCCESS::"
	sendStatusAPI
}

# install package function
function apt_command {
  for command in "$@"
  do
    /bin/echo "> Execute apt command simulation on \""$command"\"";
    if [ "$command" != "update" ]; then
      # simulate an update (dependency check)
      /usr/bin/apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y --force-yes --simulate $command  || { /bin/echo "> Simulation failed ($1)"; fail; }

			# download packages (check network)
      /usr/bin/apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y --force-yes --download-only $command  || { /bin/echo "> Download failed ($1)"; fail; }
    fi
  done
  # simulation succeeded and all packages are downloaded
  for command in "$@"
  do
    /bin/echo "> Execute apt command on \""$command"\"";
    /usr/bin/apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y --force-yes $command  || { /bin/echo "> Upgrade failed ($1)"; fail; }
  done
}



function firewall_save_old_iptables {
	log "Upgrade" "Replacing IPTables with NFTables"
	log "Upgrade" "Installing NFTables package with apt-get"
	apt_command "install nftables"
	log "Upgrade" "Install iptables compat package"
	/usr/bin/apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y --force-yes install iptables-nftables-compat 2> /dev/null > /dev/null
	log "Firewall" "Saving the old iptables to convert them to NFTables"
	/sbin/iptables-save > /tmp/iptables-old-4.txt
	/sbin/ip6tables-save > /tmp/iptables-old-6.txt
	log "Upgrade" "Converting ipgrables to NFTables"
	iptables-restore-translate -f /tmp/iptables-old-4.txt > /tmp/nftables-new.nft
	ip6tables-restore-translate -f /tmp/iptables-old-6.txt >> /tmp/nftables-new.nft
	log "Upgrade" "Removing comments from NFTables file"
	/bin/sed -i.bak -E "s/comment \"(.*)\"//" /tmp/nftables-new.nft
}

function firewall_convert_old_iptables_to_new_nftables {
	# log "Upgrade" "Execute new NFTables rules"
	# /usr/sbin/nft -f /tmp/nftables-new.nft
	log "Upgrade" "Preparing /etc/nftables.conf for next reboot"
	/bin/cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f

# Flush the rule set
flush ruleset

EOF
	/bin/cat /tmp/nftables-new.nft >> /etc/nftables.conf
	/bin/chmod +x /etc/nftables.conf
	log "Upgrade" "Enable NFTables in systemctl"
	/bin/systemctl enable nftables
}

im_check_python() {
	_python=`command -v python`
	if [ $? -eq 0 ]; then
		return 0
	fi
	_python3=`command -v python3`
	if [ $? -eq 0 ]; then
		python_command=python3
		return 0
	fi
}

im_getIMSettings(){
_db_output=$(sudo -u postgres /usr/bin/psql -tAq --dbname database_single -c "SELECT VALUE FROM parameter WHERE name='INSTANCE_MANAGER_STATUS';")
im_is_enabled=$([[ "$(echo $_db_output | ${python_command} -c "import sys, json; parsed = json.load(sys.stdin); print(parsed['isEnabled']);")" == "True" ]] && echo 1 || echo 0 2> /dev/null)
im_management=$([[ "$(echo $_db_output | ${python_command} -c "import sys, json; parsed = json.load(sys.stdin); print(parsed['isManagementEnabled']);")" == "True" ]] && echo 1 || echo 0 2> /dev/null)
im_dataaccess=$([[ "$(echo $_db_output | ${python_command} -c "import sys, json; parsed = json.load(sys.stdin); print(parsed['isDataAccessEnabled']);")" == "True" ]] && echo 1 || echo 0 2> /dev/null)
}

im_setIMSettings(){
if [[ "$im_is_enabled" -eq 1 ]]; then
		/bin/echo "> Update IM Settings /usr/sbin/install-instance-manager 1 $im_management $im_dataaccess"
		/usr/sbin/install-instance-manager 1 $im_management $im_dataaccess
fi
}

function flag_if_dphys-swapfile_installed {
	/bin/systemctl status dphys-swapfile
	if [ $? -eq 0 ]; then
		touch /tmp/TCX_UPGRADE_DPHYS_IS_ENABLED
	fi
}

function stop_3cx_services {
	/usr/sbin/3CXStopServices
}

function start_3cx_services {
	/usr/sbin/3CXStartServices
}

function disable_apt_daily_timer {
	/bin/systemctl stop apt-daily.timer
}

function enable_apt_daily_timer {
	/bin/systemctl start apt-daily.timer
}

function disable_dphys-swapfile {
	if [ -f /tmp/TCX_UPGRADE_DPHYS_IS_ENABLED ]; then
		/sbin/dphys-swapfile uninstall
		/bin/systemctl disable dphys-swapfile.service
		apt_command "remove dphys-swapfile"
	fi
}

function enable_dphys-swapfile {
	if [ -f /tmp/TCX_UPGRADE_DPHYS_IS_ENABLED ]; then
		apt_command "install dphys-swapfile"
		/bin/systemctl enable dphys-swapfile.service
	fi
}

function disable_3cx_update {
	mv /usr/sbin/3CXServicePackVersion /tmp/3CXServicePackVersion.backup
}

function activate_3cx_update {
	if [ ! -f /usr/sbin/3CXServicePackVersion ]; then
		mv /tmp/3CXServicePackVersion.backup /usr/sbin/3CXServicePackVersion
	fi
}

function check_apt_lock {
	/bin/fuser /var/lib/apt/lists/lock > /dev/null 2> /dev/null
	if [ $? -eq 0 ]; then
		/bin/fuser /var/lib/apt/lists/lock
		log "Failed" "Output of ps aux (apt lock)"
		AS=`/bin/fuser /var/lib/apt/lists/lock | /usr/bin/cut -d ":" -f2`

		# Attempt to kill a specific process stuck from 2021
		IS_STUCK=`ps -eo pid,lstart | grep $AS | grep -o '....$'`
		if [ "$IS_STUCK" == "2021" ]; then
			/bin/kill -9 $AS
			if [ $? -eq 0 ]; then
				log "Killed apt lock from 2021. Continuing..."
				return
			fi
		fi

		/bin/ps aux --forest | grep $AS
		false
		check_fail "Preparation" "There seems to be an apt file lock in place. Don't touch anything."
	fi
	/bin/fuser /var/lib/dpkg/lock > /dev/null 2> /dev/null
	if [ $? -eq 0 ]; then
		/bin/fuser /var/lib/dpkg/lock
		false
		check_fail "Preparation" "There seems to be an dpkg file lock in place. Don't touch anything."
	fi
}

function restore_source_lists {
	if [ -d "/tmp/sources_bk" ]; then
		rm -rf /etc/apt/sources.list.d/*
		/bin/cp -f /tmp/sources_bk/* /etc/apt/sources.list.d/ 	
	fi
	if [ -f "/tmp/sources.list.backup" ]; then
		/bin/cp /tmp/sources.list.backup /etc/apt/sources.list
	fi
}

function fail {
	/bin/cp $LOG_UPDATE $FLAG_UPDATE_FAIL
	/bin/rm -f $FLAG_UPDATE_RUNNING
	restore_source_lists
	activate_3cx_update
	start_3cx_services
	enable_apt_daily_timer
	enable_dphys-swapfile
	/bin/echo "::FAIL::"
	log "Failed" "Output of ps aux"
	/bin/ps aux 2>&1
	log "Failed" "Output of journalctl"
	/bin/journalctl -xe 2>&1
	log "Failed" "Output of /var/log/nginx/error.log"
	/bin/cat /var/log/nginx/error.log 2>&1 | /usr/bin/tail -1000
	log "Failed" "Output of /var/log/nginx/access.log"
	/bin/cat /var/log/nginx/access.log 2>&1 | /usr/bin/tail -1000
	log "Failed" "Output of /var/log/syslog.log"
	/bin/cat /var/log/syslog 2>&1 | /usr/bin/tail -1000
	sendStatusAPI
	exit -1;
}

function check_fail {
	if [ "x$?" != "x0" ]; then
		/bin/echo -e "\e[31m[`date +"%H:%M"`] $1: $2 - $?\e[39m"
		/bin/cp $LOG_UPDATE $FLAG_UPDATE_FAIL
		/bin/rm -f $FLAG_UPDATE_RUNNING
		fail
	fi
}

function check_if_3cx_is_installed {
    dpkg -l | grep 3cxpbx  2> /dev/null > /dev/null
    if [ "x$?" != "x0" ]; then
		log "Preparation" "3CX is not installed."
		exit -1
	fi
}



function switch_to_3cx_new_repo {

	# Add keys for third party repos
	if [ ! -f /usr/bin/curl ]; then
		apt install curl -y
	fi

	if [ ! -f /usr/lib/apt/methods/https ]; then
		apt install apt-transport-https -y
	fi
	
	# Backup old debian package sources (in case we need to switch back)
	/bin/cp -f /etc/apt/sources.list /tmp/sources.list.backup

	if [ ! -d "/tmp/sources_bk" ]; then
		mkdir /tmp/sources_bk
	fi

	/bin/cp -f /etc/apt/sources.list.d/* /tmp/sources_bk/

	# Remove all third party repos/sources
	# rm -rf /etc/apt/sources.list.d/*

	# Add 3CX key 
	if [ ! -f /usr/bin/gpg ]; then
		apt install gpg -y
		if [ "x$?" != "x0" ]; then
			check_fail "Preparation" "Unable to install gpg. Aborting."
		fi
	fi

	wget -O- https://repo.3cx.com/key.pub | gpg --dearmor | sudo tee /usr/share/keyrings/3cx-archive-keyring.gpg > /dev/null

	# Set 3CX Debian Stretch repos
	if [ "x$ARCHITECTURE" = "xarm64" ]; then
		/bin/echo "deb [arch=arm64 signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian/$LAST_V16_VERSION stretch main security"     > /etc/apt/sources.list
		/bin/echo "deb [arch=arm64 signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx stretch main"  								  > /etc/apt/sources.list.d/3cxpbx.list
	else
		/bin/echo "deb [arch=amd64 signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian/$LAST_V16_VERSION stretch main security"    	> /etc/apt/sources.list
		/bin/echo "deb [arch=amd64 signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx stretch main"  								 > /etc/apt/sources.list.d/3cxpbx.list
	fi


}

function check_locale_problem {
	/usr/bin/pg_lsclusters 2>&1 | /bin/grep "perl: warning"
	if [ $? -eq 0 ]; then
		/bin/cat /etc/default/locale
		/usr/bin/locale
		/usr/bin/locale -a
		/bin/false
		check_fail "Preparation" "Locales seems to be invalid. Abort."
	else
		log "Preparation" "Checking locales"
	fi
}

# Detach script if necessary
if [ "x$1" != "xdetach" ]; then
	if [ "x$1" != "xrunstandalone" ]; then
		log "Preparation" "Detach script"
	  /usr/bin/setsid sh -c "exec $SCRIPT 'runstandalone' 2>&1 < /dev/null | tee -a $LOG_UPDATE 2>&1" &
	  exit 0;
	else
		log "Preparation" "Script is now running standalone"
	fi
fi

# The parent script might be there still. Wait 3 seconds for exiting.
/bin/sleep 1
log "Preparation" "Script path is $SCRIPT"
for pid in $(/bin/pidof -x $(/usr/bin/basename $SCRIPT)); do
    if [ $pid != $$ ]; then
				log "Preparation" "Upgrade script $(/usr/bin/basename $SCRIPT) seeems to be already running with PID $pid"
        exit 1
    fi
done

if [ -f $FLAG_UPDATE_RUNNING ]; then
	log "Preparation" "Upgrade script $(/usr/bin/basename $SCRIPT) seeems to be already running. Found $FLAG_UPDATE_RUNNING"
	exit 1
fi

# Starting script
cd $WORKING_DIRECTORY
touch $FLAG_UPDATE_RUNNING

log "Starting" "Backup script $SCRIPT"
log "Starting" "Backup script version: $SCRIPT_VERSION"
log "Starting" "Current directory: `pwd`"
log "Starting" "Current user: `whoami`"
log "Starting" "Current date: `date`"
log "Starting" "Current version: $VERSION_BEFORE"
log "Starting" "Architecture: $ARCHITECTURE"

# Remove old repositories
if [ -f /etc/apt/sources.list.d/saltstack.list ]; then
	log "Pre-Upgrade" "Remove salt repository if available"
	rm -f /etc/apt/sources.list.d/saltstack.list 2> /dev/null > /dev/null
fi

check_if_3cx_is_installed
flag_if_dphys-swapfile_installed
disable_3cx_update
disable_apt_daily_timer
check_locale_problem
check_apt_lock
disable_dphys-swapfile
im_check_python
im_getIMSettings
firewall_save_old_iptables

if [ "x$ARCHITECTURE" != "xarmhf" ]; then
	switch_to_3cx_new_repo
fi

log "Preparation" "Checking Debian version"

# Check LSB Release
/bin/echo $VERSION_BEFORE | grep -e "^9.*" 2> /dev/null > /dev/null
IS_VERSION_9=`/bin/echo $?`
if [ "x0" != "x$IS_VERSION_9" ]; then
	log "Preparation" "The system version is not 9 (stretch): Found version $VERSION_BEFORE"
	exit -1
else
	log "Preparation" "System is stretch ($VERSION_BEFORE). Go ahead."
fi

# Backup 3CX configuration
log "Preparation" "Preparing 3CX Backup: /var/lib/3cxpbx/Instance1/Data/Backups/rescueBackupUpgrade.zip"
/usr/bin/sudo -u phonesystem /usr/sbin/3CXBackupCmd --cfg=/var/lib/3cxpbx/Instance1/Bin/RestoreCmd.exe.config --log=$LOG_TCX_BACKUP --file=/var/lib/3cxpbx/Instance1/Data/Backups/rescueBackupUpgrade.zip --options=LIC,FQDN,PROMPTS
check_fail "Preparation" "Backup script failed. Exiting"

stop_3cx_services

function add_google_sdk_key_if_necessary {
	/usr/bin/dpkg -s google-cloud-sdk
  if [ $? -eq 0 ]; then
		log "Preparation" "Downloading latest Google SDK public key"
		# Add the key in both the old + new way
		/usr/bin/curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
		/usr/bin/wget -O- https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
		check_fail "Preparation" "Addding Google SDK GPG key failed"
	fi
}

# Check gcloud repository
add_google_sdk_key_if_necessary

# Fixing dphys-swapfile configuration
if [ -f /etc/dphys-swapfile ]; then
	sed -i '/CONF_SWAPSIZE.*$/d' /etc/dphys-swapfile
	sed -i '/CONF_MAXSWAP.*$/d' /etc/dphys-swapfile
	echo "CONF_MAXSWAP=2048" >> /etc/dphys-swapfile
	echo 3 > /proc/sys/vm/drop_caches
	sleep 10
	echo 1 > /proc/sys/vm/drop_caches
fi


# Backup the old pinning file (in case we need to switch back)
/bin/cp /etc/apt/preferences.d/3cxpbx /tmp/3cxpbx_pinning_file

# Delete pinning file
log "Preparation" "Removing old 3cxpbx pinning file"
/bin/rm -rf /etc/apt/preferences.d/3cxpbx

log "Preparation" "Switching locales to en_US and UTF-8 en_US.UTF-8 (necessary for PostgreSQL and other packages)"
if [ -z "$LANG" ]; then
	LANG="en_US.UTF-8"
	/usr/bin/localedef -i en_US -f UTF-8 en_US.UTF-8
fi

# Generate locales and set environment variables
export LANGUAGE=$LANG
export LANG=$LANG
export LC_ALL=$LANG
export LANGUAGE=$LANG
export LC_ADDRESS=$LANG
export LC_IDENTIFICATION=$LANG
export LC_MEASUREMENT=$LANG
export LC_MONETARY=$LANG
export LC_NAME=$LANG
export LC_NUMERIC=$LANG
export LC_PAPER=$LANG
export LC_TELEPHONE=$LANG
export LC_TIME=$LANG

# Fix environment for i18n
TERM=linux
unset LC_CTYPE

# Workaround
# apt-utils : Depends: apt (= 1.4.X) but 1.4.11 is installed
function apt_utils_workaround_check {
	/usr/bin/apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y --force-yes --simulate upgrade | grep -E "apt-utils : .*: apt \(= 1\.4\.[0-9]+\) .* 1.4.11.*"
	if [ "x$?" = "x0" ]; then
		log "Workaround" "Try to fix apt-utils dependency problem";
		apt_command "install apt-utils"
	fi
}

function switch_ethernet_scheme {
  if [ "x$BLOCK_DOWNGRADE" == "x1" ]; then return; fi;

	# check if network inetface is old scheme
	/sbin/ifconfig | /bin/grep eth0
	if [ "x$?" == "x0" ]; then
  	# backup for rollback
  	/bin/cp /etc/default/grub /tmp/grub.backup
  	/bin/sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT/ {/net.ifnames=0/! s/\(.*\)"/\1 net.ifnames=0"/}' /etc/default/grub
  	/bin/ln -s /dev/null /etc/systemd/network/99-default.link
	fi
}

function switch_googld_sdk {
  # unhold package if it is on hold
  if [ "x$GOOGLE_SDK" == "x1" ]; then
    /usr/bin/apt-mark unhold google-cloud-sdk
    return;
  fi
  # check if Google Cloud SDK is installed
  GOOGLE_SDK=0
  /usr/bin/dpkg -s google-cloud-sdk
  if [ $? -eq 0 ]; then
    GOOGLE_SDK=1
    /usr/bin/apt-mark hold google-cloud-sdk
  fi
}

# Set 3CX Debian Buster repos
function switch_package_sources {

	if [ ! -d "/tmp/sources_bk" ]; then
		mkdir /tmp/sources_bk
	fi


  if [ "x$BLOCK_DOWNGRADE" == "x1" ]; then return; fi;

	if [ "x$ARCHITECTURE" = "xarmhf" ]; then
		/bin/cp -f /etc/apt/sources.list /tmp/sources.list.backup
		/bin/cp -f /etc/apt/sources.list.d/* /tmp/sources_bk/
		/bin/echo "deb http://downloads-global.3cx.com/downloads/debian buster main" > /etc/apt/sources.list.d/3cxpbx.list
		/bin/echo "deb [arch=armhf] http://downloads-global.3cx.com/downloads/debian buster-testing main" > /etc/apt/sources.list.d/3cxpbx-testing.list
		/bin/sed -i s/stretch/buster/g /etc/apt/sources.list
	elif [ "x$ARCHITECTURE" = "xarm64" ]; then
		/bin/echo "deb [arch=arm64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian/$CURRENT_V18_VERSION buster main"      	> /etc/apt/sources.list
		/bin/echo "deb [arch=arm64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian-security/$CURRENT_V18_VERSION buster main" >> /etc/apt/sources.list
		/bin/echo "deb [arch=arm64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx buster main"  								> /etc/apt/sources.list.d/3cxpbx.list
		/bin/echo "deb [arch=arm64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx buster-testing main"  						> /etc/apt/sources.list.d/3cxpbx-testing.list
	else
		/bin/echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian/$CURRENT_V18_VERSION buster main"     		> /etc/apt/sources.list
		/bin/echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian-security/$CURRENT_V18_VERSION buster main" >> /etc/apt/sources.list
		/bin/echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx buster main"  								> /etc/apt/sources.list.d/3cxpbx.list
		/bin/echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx buster-testing main"  						> /etc/apt/sources.list.d/3cxpbx-testing.list
	fi


  # Replace all occurrences of stretch in the /etc/apt/sources.list.d/ 3cxpbx.list
  /bin/sed -i s/stretch/buster/g /etc/apt/sources.list.d/*
}

# Check if at least 256 MB are available
AVAILABLE_DISK_SPACE=`/bin/echo $(($(stat -f --format="%a*%S" /)))`
if [ $AVAILABLE_DISK_SPACE -lt 1006870912 ]; then
	log "Preparation" "Not enough disk space available. We need at least 1GB free disk space"
	fail;
fi

# Prepare system for Network interface naming
log "Preparation" "Switching ethernet scheme if necessary (eth0)"
switch_ethernet_scheme

# Check if Google Cloud SDK is installed
log "Preparation" "Set Google SDK package on hold for upgrade"
switch_googld_sdk

# log start time
log "Pre-Upgrade" "Initiate upgrade `/bin/date -u +"%Y-%m-%dT%H:%M:%SZ"`"

# Added cache cleanup command
log "Pre-Upgrade" "Executing apt-get clean before upgrading"
apt_command "clean"

export TCX_NO_START_SERVICES=1

# Downloading the latest pinning file for Debian 9 for RPI
log "Pre-Upgrade" "Downloading the latest pinning file for Debian 9"
if [ "x$ARCHITECTURE" = "xarmhf" ]; then
	/usr/bin/wget -O- https://downloads-global.3cx.com/downloads/v180/debianupdate/stretch.armhf.txt  > /etc/apt/preferences.d/3cxpbx
	if [ "x$?" != "x0" ]; then
		sleep 10
		/usr/bin/wget -O- https://downloads-global.3cx.com/downloads/v180/debianupdate/stretch.armhf.txt  > /etc/apt/preferences.d/3cxpbx
	fi
fi
check_fail "Upgrade" "Downloading the latest pinning file for Debian 9 FAILED"

# Force system to update to latest 9.x minor release
log "Pre-Upgrade" "Executing apt-get upgrade to upgrade to the latest Debian 9"
apt_command "update"
apt_utils_workaround_check
apt_command "upgrade"

# Remove 3CX before upgrade
log "Upgrade" "REACHING POINT OF NO RETURN - STARTING DEBIAN 10 UPGRADE AND REMOVING 3CX"
log "Upgrade" "Removing 3CX"
apt_command "remove 3cxpbx"

# Downloading the latest pinning file for Debian 10
log "Upgrade" "Downloading the latest pinning file for Debian 10"
if [ "x$ARCHITECTURE" = "xarmhf" ]; then
	/usr/bin/wget -O- https://downloads-global.3cx.com/downloads/v180/debianupdate/buster.armhf.txt > /etc/apt/preferences.d/3cxpbx
	if [ "x$?" != "x0" ]; then
		sleep 10
		/usr/bin/wget -O- https://downloads-global.3cx.com/downloads/v180/debianupdate/buster.armhf.txt > /etc/apt/preferences.d/3cxpbx
	fi
fi
check_fail "Upgrade" "Downloading the latest pinning file for Debian 10 FAILED"

# Add Debian Strech package sources
log "Upgrade" "Switching package sources from stretch to buster in /etc/apt/sources.list and /etc/apt/sources.list.d/"
switch_package_sources

# Force system to upgrade to latest 10.x major release
log "Upgrade" "apt-get update for the latest Debian 10 repositories"
apt_command "clean"

# Initiate APT_FAILED
APT_FAILED=0

# Trying to execute apt-get update manually to catch problems
/usr/bin/apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y update
if [ "x$?" != "x0" ]; then
	APT_FAILED=1
fi

# Checking downloaded packages
/usr/bin/apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y --download-only upgrade
if [ "x$?" != "x0" ]; then
	APT_FAILED=1
fi

if [ "x$APT_FAILED" != "x0" ]; then
	# Restore the old pinning file
	/bin/cp /tmp/3cxpbx_pinning_file /etc/apt/preferences.d/3cxpbx

	restore_source_lists

	# Replace all occurrences of stretch in the /etc/apt/sources.list.d/ folder
	/bin/sed -i s/buster/stretch/g /etc/apt/sources.list.d/*

	# Executing apt-get update
	apt_command "clean"
	apt_command "update"
	# Re-install 3cxpbx
	apt_command "install 3cxpbx"
	# Start 3CX services
	/usr/sbin/3CXStartServices
	# The next line "false" will ensure that check_fail will really fail
	false
	check_fail "Preparation" "There is a problem with the package download. Stopping installation and re-install 3cxpbx. There is a NFTables installation left but it shouldn't be a problem."
fi

# Fix for grub-pc
function check_for_grub {
 DEVICE_FOUND=""
 for i in `lsblk -rndbo SIZE,NAME,TRAN`; do
  /bin/echo $i
  DEVICE=`/bin/echo $i | cut -d" " -f2;`
  dd if=/dev/$DEVICE bs=512 count=1 2> /dev/null | grep -q GRUB && /bin/echo "GRUB partition found $DEVICE"
  GRUB_FOUND=$?
  if [ "x$GRUB_FOUND" == "x0" ]; then
		DEVICE_FOUND=$DEVICE
   return
  fi
 done;
}

log "Upgrade" "Grub preparation - Installing debconf-utils to handle necessary grub input"
apt_command "install debconf-utils"
log "Upgrade" "Grub preparation - Checking for grub partition"
check_for_grub
if [ "x$DEVICE_FOUND" != "x" ]; then
	log "Upgrade" "Grub preparation - Grub device found. Removing grub to reinstall it again"
	apt_command "purge grub-pc grub-common"
	log "Upgrade" "Grub preparation - Preparing grub configuration for reinstallation"
cat <<EOL | debconf-set-selections
grub-pc grub-pc/install_devices multiselect /dev/$DEVICE_FOUND
grub-pc grub-pc/install_devices_empty boolean false
EOL
	log "Upgrade" "Grub preparation - Installing grub-pc and grub-common with prepared configuration"
	apt_command "install grub-pc grub-common"
	log "Upgrade" "Grub preparation - Updating grub partition"
	update-grub
fi

# Upgrade the system
log "Upgrade" "Dist-Upgrade to the latest Debian 10. This may take a while"
apt_command "upgrade" "dist-upgrade"

# If the upgrade was successfull we shouldn't allow a downgrade from this point
export BLOCK_DOWNGRADE=1

# Update PostgreSQL to latest version
log "Post-Upgrade" "PostgreSQL - Installing latest PostreSQL 11 database"
apt_command "install postgresql-11 postgresql-client-11"
log "Post-Upgrade" "PostgreSQL - Dropping new generated empty 11 cluster"
/usr/bin/pg_dropcluster --stop 11 main
log "Post-Upgrade" "PostgreSQL - Stopping PostreSQL for upgrade"
/bin/systemctl stop postgresql # Stop all open connections
log "Post-Upgrade" "PostgreSQL - Wait 60 seconds to settle"
/bin/sleep 60 # Wait a few seconds
log "Post-Upgrade" "PostgreSQL - Upgrade old 9 database to 11 (with old 3cxpbx data)"
/usr/bin/pg_upgradecluster 9.6 main

if [ "x$?" != "x0" ]; then
	# Wait gracefully if the PostgreSQL database is not available
	log "Post-Upgrade" "PostgreSQL - Upgrade failed. Trying again"
	log "Post-Upgrade" "PostgreSQL - Wait 60 seconds to settle"
	/bin/systemctl stop postgresql # Stop all open connections
	log "Post-Upgrade" "PostgreSQL - Wait 120 seconds to settle"
	sleep 120
	log "Post-Upgrade" "PostgreSQL - Upgrade old 9 database to 11 (with old 3cxpbx data)"
	/usr/bin/pg_upgradecluster 9.6 main
fi

if [ "x$?" != "x0" ]; then
	# Wait gracefully if the PostgreSQL database is not available
	log "Post-Upgrade" "PostgreSQL - Upgrade failed. Trying again"
	log "Post-Upgrade" "PostgreSQL - Wait 60 seconds to settle"
	/bin/systemctl stop postgresql # Stop all open connections
	log "Post-Upgrade" "PostgreSQL - Wait 240 seconds to settle"
	sleep 240
	log "Post-Upgrade" "PostgreSQL - Upgrade old 9 database to 11 (with old 3cxpbx data)"
	/usr/bin/pg_upgradecluster 9.6 main
fi

check_fail "Post-Upgrade" "PostgreSQL Upgrade cluster failed failed... exiting"

# Remove old database
log "Post-Upgrade" "PostgreSQL - Drop old 9 database (with old 3cxpbx data)"
/usr/bin/pg_dropcluster --stop 9.6 main

check_fail "Post-Upgrade" "PostgreSQL Dropping old cluster failed... exiting"

log "Post-Upgrade" "PostgreSQL - Removing old PostreSQL 9 package"
apt_command "--purge remove postgresql-client-9.6 postgresql-9.6"

# Reindex database
log "Post-Upgrade" "PostgreSQL - Starting new PostgreSQL"
/bin/systemctl start postgresql
log "Post-Upgrade" "PostgreSQL - Waiting 30 seconds to settle"
/bin/sleep 30 # Wait a few seconds
log "Post-Upgrade" "PostgreSQL - Reindexing new database"
/usr/bin/sudo -u postgres reindexdb --all
check_fail "Post-Upgrade" "PostgreSQL Reindexing failed"

# Reinstall 3CX
log "Post-Upgrade" "Installing latest 3cxpbx package for Debian 10 (v18)"
apt_command "install 3cxpbx"
check_fail "Post-Upgrade" "3cxpbx package installation failed"

# Clear old packages
log "Cleaning up" "Remove old packages"
apt_command "autoremove"

# Added cache cleanup command
log "Cleaning up" "Executing apt-get clean"
apt_command "clean"

# Debriefing
log "Cleaning up" "Set Google SDK package to unhold"
switch_googld_sdk

# Remove old iptables in favour of nftables
if [ -f /usr/sbin/waagent ]; then
	# WALinuxAgent can be installed without the package management system. That is why the binary is checked directly.
	log "Cleaning up" "NOT purging iptables because it's an Azure installation"
	/bin/echo "Seems to be an Azure installation. Keeping iptables"
fi


if [ -f /etc/systemd/system/multi-user.target.wants/prometheus-node-exporter.service ]; then
	log "Cleaning up" "Prometheus - Fixing systemctl pathes"
	# Move service for unknown reason
	mv /etc/systemd/system/multi-user.target.wants/prometheus-node-exporter.service /etc/systemd/system/prometheus-node-exporter.service
	log "Cleaning up" "Prometheus - Enable prometheus-node-exporter.service"
	systemctl enable prometheus-node-exporter.service
fi

log "Finish" "Finished upgrade `/bin/date -u +"%Y-%m-%dT%H:%M:%SZ"`"

firewall_convert_old_iptables_to_new_nftables
activate_3cx_update
enable_apt_daily_timer
enable_dphys-swapfile
im_setIMSettings


VERSION_AFTER=`/usr/bin/lsb_release -r | cut -f2`
if [ ${VERSION_AFTER:0:2} == "10" ]; then
  success
	log "Finish" "New Debian version is $VERSION_AFTER"
else
  fail
fi

log "Finish" "Rebooting now"

DHCPCHK=`cat /etc/dhcp/dhclient.conf | grep -e '^send dhcp-client-identifier'`
if [ "$?" != "0" ];then
	log "Post-Upgrade" "Restoring the old dhcp-client-identifier setup"
	echo "send dhcp-client-identifier = hardware;" >> /etc/dhcp/dhclient.conf
fi


/sbin/reboot
} 2>&1 | tee -a "$LOG_UPDATE"
