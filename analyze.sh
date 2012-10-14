###################################
#
# Run through a series of checks/best practices
# and rate the installation
#
###################################

#Set some stuff we will reuse
zenuser=zenoss		#What is the user under which zenoss runs
rhel_variant=0	#Is this a RHEL Variant
zenhome=""

OK=0
WARN=0
ERROR=0

fn_ok() {
tput setaf 2
echo -n OK - 
tput sgr0
echo " $*"
OK=`expr $OK + 1`
}

fn_warn() {
tput setaf 3
echo -n WARNING - 
tput sgr0
echo " $*"
WARN=`expr $WARN + 1`
}

fn_err() {
tput setaf 1
echo -n ERROR - 
tput sgr0
echo " $*"
ERROR=`expr $ERROR + 1`
}

fn_crit() {
tput setaf 1
echo -n CRITICAL - 
tput sgr0
echo " $*"
tput setaf 1
echo "I can't continue from this condition, Aborting Test"
tput sgr0
exit 1
}


##### Start Execution of Tests
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
## *Note* We want to start with the really basic checks and get more complicated. Some checks if they fail
## will prevent future tests, so the intention is we bail on things that will prevent further tests


echo "/////////////////////////////////////////////////"
echo "/////////////////////////////////////////////////"
echo
echo "//// Analyzing on `hostname`"
echo 
echo "/////////////////////////////////////////////////"
echo "/////////////////////////////////////////////////"

#Use DMD to collect a bunch more data
echo "Connecting to your Zenoss Database to gather Additional Information"
echo "NO CHANGES WILL BE MADE"
su - zenoss -c "python $CUR_DIR/data_collect.py"

#Figure out the version of Zenoss that we are running
zenver=`cat /tmp/data_collection.txt | grep ZENOSS_VERSION | gawk '{print $3}' `
zenmajor=`echo $zenver | cut -c1`

echo "You Are Running Version $zenver"

#Are we running on el system?
if [ -f "/etc/redhat-release" ]; then
	rhel_variant=1
fi

pushd /tmp > /dev/null
#Core 4 has limited OS Support
if [ $zenmajor -gt 4 ]; then
	#Check if we are running on a supported OS
	if [ $rhel_variant -eq 1 ]; then
		fn_ok "This is a Supported OS Flavor"
	else
		fn_err "This is not a supported OS Flavor"
	fi
fi

#Check Total Memory and Cores
total_mem=`free -m | grep -i mem | gawk '{print $2}'`
procs=`cat /proc/cpuinfo | grep "^processor" | wc -l`
cores=`cat /proc/cpuinfo | grep "^cpu cores" | uniq | gawk '{print $4}'`
#Core info lifted from https://www.ibm.com/developerworks/mydeveloperworks/blogs/brian/entry/linux_show_the_number_of_cpu_cores_on_your_system17?lang=en
total_cores=`expr $procs \* $cores`

hard_req_link="http://community.zenoss.org/docs/DOC-13400"
msg_mem_to_small="${total_mem}MB is less than the suggested minimum amount of RAM. Please see $hard_req_link"
msg_mem_good="You are running with the suggested amount of RAM. $hard_req_link"
msg_min_cores="$total_cores is less than the suggested minimum amount of Cores. $hard_req_link"
msg_cores_good="You are running with the suggested amount of CPU Cores. $hard_req_link"

device_count=`cat /tmp/data_collection.txt | grep DEVICE_COUNT | gawk '{print $2}'`
if [ $device_count -ge 250 ]; then
	if [ $total_mem -lt 8192 ]; then
		fn_warn "$msg_mem_to_small"
	else
		fn_ok "$msg_mem_good"
	fi
	if [ $total_cores -lt 4 ]; then
		fn_warn "$msg_min_cores"
	else
		fn_ok "$msg_cores_good"
	fi
	if [ $device_count -ge 500 ]; then
		if [ $total_mem -lt 16384 ]; then
			fn_warn "$msg_mem_to_small"
		else
			fn_ok "$msg_mem_good"
		fi
		if [ $total_cores -lt 8 ]; then
			fn_warn "$msg_min_cores"
		else
			fn_ok "$msg_cores_good"
		fi
	fi
else
	if [ $total_mem -lt 4096 ]; then
		fn_warn "$msg_mem_to_small"
	else
		fn_ok "$msg_mem_good"
	fi
	if [ $total_cores -lt 2 ]; then
		fn_warn "$msg_min_cores"
	else
		fn_ok "$msg_cores_good"
	fi
fi

#Confirm we have a zenoss user
cat /etc/passwd | grep "${zenuser}" > /dev/null
if [ $? -eq 0 ]; then
	fn_ok "$zenuser User Exists"
else
	fn_crit "$zenuser User Doesn't Exist"
fi
. /home/zenoss/.bashrc

#Check for Daemons that are not running
if [ `su - zenoss -c "zenoss status" | grep -c "not running"` == 0 ]; then
  fn_ok "All Daemons Appear to be running"
else
 IFS_ORIG=$IFS
 IFS=$'\n'
 for line in `su - zenoss -c "zenoss status" | grep "not running"`; do
	fn_err $line
 done
 IFS=$IFS_ORIG
fi

#Check that required services are running
if [ $rhel_variant -eq 1 ]; then
	#Service command is rhel centric, figure out how to check these services on other os' when the time comes
	#Seems mysql service name varies between mysql and mysqld. Lets handle either
	if [ `chkconfig --list | grep -c -i mysqld` -gt 0 ]; then
		mysql_service="mysqld"
	else
		mysql_service="mysql"
	fi
	service $mysql_service status | grep -i running > /dev/null && fn_ok "mysql service is running" || fn_err "mysql service is not running"
	if [ $zenmajor -eq 4 ]; then
		service rabbitmq-server status | grep uptime > /dev/null && fn_ok "rabbitmq-server service is running" || fn_err "rabbitmq-server service is not running"
		service memcached status | grep -i running > /dev/null && fn_ok "memcached service is running" || fn_err "memcached service is not running"
	fi
fi

#Now lets do some sanity checking of RabbitMQ Setup
if [ $zenmajor -eq 4 ]; then
	amqp_user=`cat $ZENHOME/etc/global.conf | grep amqpuser | gawk '{print $2}'`
	amqpvhost=`cat $ZENHOME/etc/global.conf | grep amqpvhost | gawk '{print $2}'`
	rabbitmqctl list_users | grep $amqp_user > /dev/null && fn_ok "Configured amqpuser (\"$amqp_user\") exists inside rabbitmq" || fn_err "Configured amqpuser (\"$amqp_user\") missing inside rabbitmq"

	#Check Permissions are the default
	rabbitmqctl list_user_permissions -p $amqpvhost $amqp_user | grep -e "\.\*\s*\.\*\s*\.\*\s*" > /dev/null
	if [ $? == 0 ]; then
		fn_ok "RabbitMQ Permissions for user $amqp_user on vhost $amqpvhost appear to be default"
	else
		fn_warn "RabbitMQ Permissions for user $amqp_user on vhost $amqpvhost are not the default."
	fi
fi

#Lets check permissions on /dev/shm
#I can't explain why, but if [ `sudo -u zenoss test -r /tmp/test.txt1` ] always failed... 
#Taking a much uglier appoach......
shm="/dev/shm"
sudo -u zenoss test -r $shm
shm_can_read=$?
sudo -u zenoss test -x $shm
shm_can_execute=$?
sudo -u zenoss test -w $shm
shm_can_write=$?

if [ $shm_can_read -eq 0 ]; then
	if [ $shm_can_execute -eq 0 ]; then
		if [ $shm_can_write -eq 0 ]; then
			fn_ok "/dev/shm has the proper permissions"
		else
			fn_err "/dev/shm is not writable by the Zenoss user. Please refer to $shm_perm_link"
		fi
	else
		fn_err "/dev/shm is not executable by the Zenoss user. Please refer to $shm_perm_link"
	fi
else
	fn_err "/dev/shm is not readable by the Zenoss user. Please refer to $shm_perm_link"
fi 

#Check Service Packs... This might get ugly....
if [ "$zenver" == "4.2.0" ]; then
	if [ -f $ZENHOME/ServicePacks/INSTALLED ]; then
		fn_ok "You Appear to have installed at least one Service Pack for 4.2.0"
	else
		fn_warn "You appear to be running 4.2.0 without any Service Packs. Please see http://wiki.zenoss.org/Zenoss_Core_4.2.0_SP1"
	fi
fi

#Check File Descriptors
if [ `cat /etc/sysctl.conf | grep fs.file-max` ]; then
	fn_ok "Appears you have explicitly configured file descriptors. Please see http://community.zenoss.org/docs/DOC-13428"
else
	if [ `cat /etc/security/limits.conf | grep -c $zenuser` -gt 0 ]; then
		fn_ok "Appears you have explicitly configured file descriptors. Please see http://community.zenoss.org/docs/DOC-13428"
	else
		fn_warn "You have not explicitly configured file descriptors per http://community.zenoss.org/docs/DOC-13428"
	fi
fi


#Does it make sense to auto run tuner?
#echo "Running MySQLTuner (No Changes Will Be Made)"
#durl="http://mysqltuner.com/mysqltuner.pl"
#tuner_results=/tmp/mysqltuner_results_`date +%s`.txt
#wget -q $durl -O mysqltuner.pl || fn_err "Failed to download MySQL Tuner from $$durl"
#perl mysqltuner.pl > $tuner_results
#echo "You can review the mysqltuner results by typing cat $tuner_results"

#Checks to Add
## Check that Memcached CACHESIZE is not the default
## sysctl fs.file-max
## Check Service Pack is installed $ZENHOME/ServicePacks/INSTALLED

#Let the user know their 'score'
prate=`echo - | awk "{ print $OK/$(($OK+$WARN+$ERROR))*100}"`
prate=${prate/.*}
echo -n "Your Score : "
if [ $prate -ge 90 ]; then
	tput setaf 2
elif [ $prate -ge 80 ];then
	tput setaf 3
else
	tput setaf 1
fi
echo "${prate}%"
tput sgr0

echo "Please review the output above for suggestions and recommendations to improve your Zenoss installation"
popd > /dev/null
cat << EOF
If you are interested in additional information around performance tuning, please review:
* http://community.zenoss.org/message/51111
* http://community.zenoss.org/docs/DOC-13402
EOF

