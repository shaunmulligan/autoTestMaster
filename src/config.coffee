# Default test config
# some of this stuff is legacy
SLAVE_APP_NAME = process.env.SLAVEAPP or 'rpiSlave'
SLAVE_APP_ID = process.env.SLAVE_APP_ID or 9155
TOKEN = process.env.TOKEN or null
USERNAME = process.env.USERNAME
USER_PASS = process.env.USER_PASS
SSID = process.env.SSID or 'Techspace'
WIFI_PASS = process.env.WIFI_PASS or 'cak-wy-rum'
TEST_ENV_TARGET = process.env.TEST_ENV_TARGET or 'https://api.resin.io'
IMG_PATH = process.env.IMG_PATH or './test.img'
DEV_TYPE = process.env.DEV_TYPE or 'raspberry-pi2'

module.exports =
	uuid: ''
	log: null
	state: null
	#lastEvent is a hack to allow this to work with old polling code on jenkins
	lastEvent: null
	error: ''
	timeout: false
	states: null
	token: TOKEN
	sTim: null
	Utoken: TOKEN
	appName: SLAVE_APP_NAME
	img:
		appId: SLAVE_APP_ID
		network: 'ethernet'
		wifiSsid: SSID
		wifiKey: WIFI_PASS
		uiHost: ''
		apiHost: TEST_ENV_TARGET
		pathToImg: IMG_PATH
		devType: DEV_TYPE
	credentials:
		email: USERNAME
		password: USER_PASS
