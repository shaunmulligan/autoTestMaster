express = require 'express'
AutoTester = require './stateMachine'
config = require './config'
bunyan = require('bunyan')

logLevel = process.env.LOG_LEVEL or 'info'
logSettings =
	name: 'server'
	level: logLevel
	streams: [
		{
        type: 'rotating-file',
        path: '/data/server.log',
        period: '1d',   # daily rotation
        count: 3,       # keep 3 back copies
				level: 'debug'
    },
		{
			level: logLevel,
			stream: process.stdout
		}
	]
log = bunyan.createLogger logSettings

startTime = 0

app = express()
fsm = new AutoTester
	initial_data: config #pass the default test config in here
	initial_state: 'Waiting'

app.get '/jstatus', (req, res) ->
	log.info 'Got /jstatus request'
	if !fsm.current_state_name? or fsm.current_state_name == 'Waiting'
		mode = 'free'
		state = 'Waiting'
		if config.lastEvent == 'rpi booted'
			state = config.lastEvent
		if config.lastEvent == 'testing finished with error'
			state = config.lastEvent
	else
		mode = 'testing'
		state = config.lastEvent #fsm.current_state_name

  resData =
		state: state
		error: config.error
		started: startTime
		now: Date.now()
	res.json( resData )

# tests need this: jenkins will ping to check if device is online
app.get '/ping', (req, res) ->
	if !fsm.current_state_name? or fsm.current_state_name == 'Waiting'
		mode = 'free'
		state = 'Waiting'
	else
		mode = 'testing'
		state = fsm.current_state_name

	log.info 'Got /ping request, mode is ' + mode

	response =
		resp: 'ok'
		mode: mode
		state: state
		started: startTime
		now: Date.now()

	res.json response

# tests need this: jenkins will trigger this
app.get '/start', (req, res) ->
	log.info 'Got Start testing request from: '  +  req.ip

	config.appName = req.query.app
	config.img.appId = req.query.appId
	config.img.network = req.query.net
	config.img.uiHost = req.query.uiHost
	config.img.apiHost = req.query.apiHost
	config.credentials.email = req.query.username
	config.credentials.password = req.query.password

	log.debug { config: config.img }

	if fsm.current_state_name != 'Waiting'
		log.info 'Test in progress: [STATE] = ' + fsm.current_state_name
		mode = 'testing'
		state = config.lastEvent #fsm.current_state_name
	else
		log.info 'Starting test'
		mode = 'free'
		state = 'started'
		config.lastEvent = 'started'
		startTest(config)

	response =
		resp: 'ok'
		mode: mode
		state: state
		started: startTime
		now: Date.now()

	res.json response

startTest = (testData) ->
	log.debug { img: testData.img }
	log.info 'Starting State Machine'
	startTime = Date.now()
	fsm.config.initial_state = 'Initialize'
	fsm.current_state_name = 'Initialize'
	fsm.current_data = testData
	fsm.start()

log.info 'Starting Server'
app.listen(process.env.PORT or 8080)
