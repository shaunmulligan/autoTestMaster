## Auto Test Master

#### TODO:

* set DEV_TYPE for different device types
* set the update.lock so that container cant be restarted during a test
* enable a way to shut down ethernet Network
* detect power connected on slave
* switch to promise based GPIO: https://github.com/k2wanko/node-pi-gpio
* ability to change target test env (prod or staging)
	* set RESINRC_BASE_URL to resin.io or resinstaging.io
* enable console on prod devices, so can talk to bootloader, kernel and HostOS
