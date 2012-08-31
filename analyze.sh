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

pushd /tmp > /dev/null
#Check if we are running on a supported OS
if [ -f "/etc/redhat-release" ]; then
	rhel_variant=1
	fn_ok "This is a Supported OS Flavor"
else
	fn_err "This is not a supported OS Flavor"
fi

#Confirm we have a zenoss user
cat /etc/passwd | grep $zenuser > /dev/null && fn_ok "$zenuser User Exists" || fn_err "$zenuser User Doesn't Exist"
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
if [ $rhel_variant == 1 ]; then
	#Service command is rhel centric, figure out how to check these services on other os' when the time comes
	service mysql status | grep -i running > /dev/null && fn_ok "mysql service is running" || fn_err "mysql service is not running"
	service rabbitmq-server status | grep uptime > /dev/null && fn_ok "rabbitmq-server service is running" || fn_err "rabbitmq-server service is not running"
	service memcached status | grep -i running > /dev/null && fn_ok "memcached service is running" || fn_err "memcached service is not running"
fi

#Now lets do some sanity checking of RabbitMQ Setup
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

echo "Running MySQLTuner (No Changes Will Be Made)"
durl="http://mysqltuner.com/mysqltuner.pl"
wget -q $durl && perl mysqltuner.pl || fn_err "Failed to download MySQL Tuner from $$durl"

#Checks to Add
## Check that Memcached CACHESIZE is not the default
## sysctl fs.file-max

#Let the user know their 'score'
prate=`echo - | awk "{ print $OK/$(($OK+$WARN+$ERROR))*100}"`
prate=${prate/.*}
echo -n "Pass Rate (Excluding MySQLTuner Recommendations): "
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
