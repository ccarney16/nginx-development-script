# Nginx Web Development Script #

This is a bash script for web developers on Unix platforms. This script preps a development environment for usage right away.

Requires git and nginx to operate

## Parameters ##

	--help - returns this screen
	--repo=[git url] - changes the repo for the command for the current session
	--root=[location] - changes the root location for the current session
	--default-repo=[git url] - changes the git repo
	--default-root=[location] - changes the current root for the environment
	--rebuild-env - rebuilds the environment using the current repo in the config
	--test-config - test the development config
	--stop - stops the nginx environment

## TODO ##

Allow nginx to run in the front
