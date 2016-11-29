#!/bin/bash

# This script is for UNIX development environments for
# nginx. 

### START VARIABLES ###
# These are where all variables needed for the program
_VER="0.1"

nginxLocations=(
	"/bin/nginx"
	"/sbin/nginx"
	"/usr/bin/nginx"
	"/usr/sbin/nginx"
	"/usr/local/bin/nginx"
)

# Our path to the nginx executable
NginxPath=""

# Path combined with the config arguements
NginxBaseArgs=""

# Version of nginx that will be running
NginxVersion=""

### END VARIABLES ###

## START CONFIG ##

#Environmental Config

ENV_ConfigFile="$HOME/.nginx-dev.conf"

# Location for all site configs
ENV_SiteConfigs="configs/per-site"

# Web Data
ENV_WebRoot="websites"

# Web Data Content
ENV_DefaultWebContent="data"

# Main nginx config
ENV_NginxConfig="configs/nginx.conf"

#Main script for each repo
ENV_PRIMARYSCRIPT="setup.sh"

# Global Config*

# Our main repo location for git
GLOBAL_GitRepo="https://github.com/ccarney16/nginx-development"

# The main Root Environment for all nginx development
GLOBAL_RootEnv="$HOME/nginx-development"

### END CONFIG ###


### START REPO VARIABLES ###

# Default config for websites
REPO_DEFAULTCONFIG="configs/site-default.conf"

# Makes required directories
REPO_MKDIR=""

### END REPO VARIABLES ###

### START FUNCTIONS ###

# Returns the help message
function returnHelp {
	echo ""
	echo "Nginx Web Development Script v$_VER"
	echo "Usage: $0 COMMAND [options]"
	echo ""
	echo "Main commands:"
	echo ""
	echo " start                        starts the nginx environment"
	echo " stop                         stops the nginx environment"
	echo " sites                        main site command"
	echo "    list                      list all the sites under the environment"
	echo "    add [www.example.dev]     adds a new site under the config"
	echo "    remove [www.example.dev]  removes a website"
	echo "    clean [www.example.dev]   rebuilds a sites configuration to repo default"
	echo ""
	echo " config                       main global config command"
	echo "    list                      lists all the global variables"
	echo "    set VAR=\"var\"             sets a variable in the global config, leave \"\" for nothing"
	echo ""
	echo " rebuild-env                  rebuilds the development environment from the selected repo"
	echo " test-nginx-config            tests the current root nginx config"
	echo "" 
	echo "Built in options:"
	echo ""
	echo " --help - returns this screen"
	echo ""
	echo "Repo Options: "
	echo " Not implemented yet..."
}

# Finds out if we have nginx installed in these locations
function findNginx {
	for loc in ${nginxLocations[@]}; do
		if [[ -f "$loc" && -x "$loc" ]]; then
			NginxPath="$loc"
			return
		fi  
	done
}

function saveConfig {
	echo "#This config is for nginx-dev" > $ENV_ConfigFile
	echo "RootEnv=$GLOBAL_RootEnv" >> $ENV_ConfigFile
	echo "GitRepo=$GLOBAL_GitRepo" >> $ENV_ConfigFile 
}

function readConfig {
	if [ -f "$1" ]; then
		while read -r line; do 
			if [[ "$line" != \#* ]]; then
				IFS='=' read -r -a arr <<< "$line"
				export $2_${arr[0]}="${arr[1]}"
			fi
		done < $1
	else 
		echo -e "Error! unable to find $1!"
		exit
	fi 	
}

# Our main setup section, uses git to build a new environment
function setupEnvironment {
	git clone -b internal-develop $GLOBAL_GitRepo $GLOBAL_RootEnv
	wait 

	#Clean out all REPO variables
	compgen -v | grep -E "REPO_" | while read -r var; do
		unset $var
	done 
	wait

	readConfig "$GLOBAL_RootEnv/main.conf" REPO
	wait

	. "$GLOBAL_RootEnv/$ENV_PRIMARYSCRIPT"
	wait

	echo "Creating directories..."
	IFS=', ' read -r -a dirEntries <<< "$REPO_MKDIR"
	for dir in ${dirEntries[@]}; do 
		mkdir -v $GLOBAL_RootEnv/$dir
	done;

	# Make the website data folder
	if [ ! -d $GLOBAL_RootEnv/$ENV_WebRoot ]; then 
		mkdir -v $GLOBAL_RootEnv/$ENV_WebRoot
	fi

	#Now make the per site
	if [ ! -d $GLOBAL_RootEnv/$ENV_SiteConfigs ]; then
		mkdir -v $GLOBAL_RootEnv/$ENV_SiteConfigs
	fi

	# Set all variables
	setup_initRepo

	echo -e "Rebuilding variables in nginx config files\e[0m"
	
	patchFile "$GLOBAL_RootEnv/$ENV_NginxConfig"

	# Add the default site
	addSite "localhost"
}

# Allows us to delete the environment and start from scratch
function rebuildEnvironment {
	local stay=true
	while $stay; do
		read -p "Do you want to rebuild the environment (all data will be lost!) [Y/n] " yn
		case $yn in
		[Yy]* )
			rm -dfr $GLOBAL_RootEnv
			setupEnvironment
			echo "Environment files are located in \"$GLOBAL_RootEnv\"."
			echo "Environment has been setup, make sure that you have everything configured before starting."
			echo "Please issue this command again to fully start nginx."
			stay=false
			;;
		[Nn]* )
			echo "Rebuild Aborted"
			stay=false
			;;
		esac
	done  
}

# Alright lets run Nginx
function runNginx {
	if [ -f $GLOBAL_RootEnv/run/nginx.pid ]; then
		echo "nginx is already running!"
		exit 1
	fi

	setup_onStart

	echo "Starting nginx, please hold..."
	
	# Supress all info on screen, instead bringing it to a text file
	$NginxBaseArgs 2> $GLOBAL_RootEnv/startup.txt

	sleep 1
	if [ -f $GLOBAL_RootEnv/run/nginx.pid ]; then
		PID=$(cat $GLOBAL_RootEnv/run/nginx.pid)
		echo "nginx is now runnning; PID.$PID"	
	else 
		echo "Nginx did not start! Check $GLOBAL_RootEnv/startup.txt for more info"
	fi
}

# Lets stop Nginx
function stopNginx {
	if [ -f $GLOBAL_RootEnv/run/nginx.pid ]; then
		echo -e "Stopping Nginx..."
		$NginxPath -c $GLOBAL_RootEnv/configs/nginx.conf -s stop 2> /dev/null
		sleep 1
	else 	
		echo "Nginx is currently not running"
	fi
}

function textNginxConfig() {
	echo "Issuing test to nginx..."
	$NginxBaseArgs -t
}

function addSite {
	if [ -f $GLOBAL_RootEnv/$ENV_SiteConfigs/$1.conf ]; then
		echo "Error! $1 already exists (maybe do a site rebuild instead?)"
		exit
	fi 

	# Always set to Override
	local ENV_ServerName="$1"

	if [ ! -d $GLOBAL_RootEnv/$ENV_WebRoot/$ENV_ServerName ]; then
		mkdir $GLOBAL_RootEnv/$ENV_WebRoot/$ENV_ServerName
	fi

	# init before writing to the config file
	setup_onAdd

	if [ -f $GLOBAL_RootEnv/$REPO_DEFAULTCONFIG ]; then
		cp $GLOBAL_RootEnv/$REPO_DEFAULTCONFIG $GLOBAL_RootEnv/$ENV_SiteConfigs/$1.conf

		patchFile $GLOBAL_RootEnv/$ENV_SiteConfigs/$1.conf	
	else 
		echo "Missing $REPO_DEFAULTCONFIG in the environment!"
		exit 
	fi 
}


# Patches a file with variables
function patchFile {
	if [ ! -f $1 ]; then 
		echo "Error! $1 does not exist!"
		return
	fi

	local varArray=(
		$(compgen -v | grep -E "^ENV_")
		$(compgen -v | grep -E "^CLI_") 
		$(compgen -v | grep -E "^GLOBAL_") 
		$(compgen -v | grep -E "^REPO_")
		)

	for var in ${varArray[@]}; do
		local configVar=$(echo $var | sed -e "s/ENV_//g; s/CLI_//g; s/REPO_//g; s/GLOBAL_//g;")
		sed -i "s|[{]$configVar[}]|${!var}|g" $1	
	done
}

### END FUNCTIONS ###

findNginx

# If the nginx path is not blank
if [ "$NginxPath" == "" ];
then
	echo "Nginx was not found!"
	exit 0
fi

# If the config file does not exist, create one
if [ ! -f $ENV_ConfigFile ]; then
	echo "global config does not exist, creating"
	saveConfig
fi 

# Load the global config
readConfig $ENV_ConfigFile GLOBAL

#Grab our version for Nginx
NginxVersion=$($NginxPath -v 2>&1 | sed -e "s/nginx version: //g")


# Parse args
arrLength=$#
arr=("$@")

# Split our arguements into seperate sections
mainArgs=()
optionalParameters=()
 
for ((i=0; i<$((arrLength)); i++ )); do
	if [[ ! "${arr[i]}" =~ "--" || ! "${arr[i]}" =~ "-" ]]; then
		mainArgs+=("${arr[i]}")
	else 
		optionalParameters+=("${arr[i]}")
	fi
done 

# Parse the secondary arguements as variables
for ((i=0; i<$((${#optionalParameters[@]})); i++ )); do
	if [[ ${optionalParameters[i]} =~ "--" ]]; then 
		# remove param prefix
		param=$(echo ${optionalParameters[i]} | sed -e 's/--//g')
		IFS='=' read -r -a arr <<< "$param"

		if [ ${#arr[@]} -gt 1 ]; then
			export CLI_${arr[0]}="${arr[1]}"	
		else 
			#Consider as a boolean value if there is no assigned variable 
			export CLI_${arr[0]}=true
		fi
	fi 
done

#Need to make sure our development environment is there
if [ ! -d $GLOBAL_RootEnv ]; then
	echo -e "\e[1m\e[91m Root Directory does not have an environment! Creating one..."
	setupEnvironment
	echo -e "\e[34mEnvironment files are located in \"$GLOBAL_RootEnv\"."
	echo -e "Environment has been setup, make sure that you have everything configured before starting."
	echo -e "Please issue '$0 start' to start the environment .\e[0m"
	exit 1
fi

# Load repo config
readConfig "$GLOBAL_RootEnv/main.conf" REPO
wait

# Setup base args for nginx
NginxBaseArgs="$NginxPath -c $GLOBAL_RootEnv/configs/nginx.conf"

if [[ -v $CLI_help ]]; then
	. "$GLOBAL_RootEnv/$ENV_PRIMARYSCRIPT"
	returnHelp
	exit 1
fi

if [ ${#mainArgs[@]} -gt 0 ]; then
	case "${mainArgs[0]}" in
		start )
			. "$GLOBAL_RootEnv/$ENV_PRIMARYSCRIPT"
			# run the web server
			runNginx
			exit
			;;
		site )
			echo "not implemented yet" 
			;;
		stop )
			. "$GLOBAL_RootEnv/$ENV_PRIMARYSCRIPT"
			stopNginx
			exit
			;;
		config )
			. "$GLOBAL_RootEnv/$ENV_PRIMARYSCRIPT"
			if [ ${#mainArgs[@]} -gt 1 ]; then
				case ${mainArgs[1]} in 
					list )
						echo "Config Variable List"
						compgen -v | grep GLOBAL_ | while read -r var; do
							configVar=$(echo $var | sed -e "s/GLOBAL_//g")
							echo -e "\e[1m$configVar\e[0m: ${!var}"
						done
						echo ""
						;;
					set )
						echo "not implemented yet"
						;;
				esac
			else 
				echo -e "Error! No config setting specified, please run nginx-dev --help for more info"
			fi 
			;;
		rebuild-env )
			rebuildEnvironment
			exit 1
			;;
		test-nginx-config )
			textNginxConfig
			;;
	esac
else 
	echo "Error! No commands were issued!"
fi