express = require 'express'
AutoTester = require './stateMachine'
config = require './config'

startTime = 0

app = express()
fsm = new AutoTester
	initial_data: config #pass the default test config in here
	initial_state: 'Waiting'

app.get '/jstatus', (req, res) ->
	console.log 'Got /jstatus request'
	if !fsm.current_state_name? or fsm.current_state_name == 'Waiting'
		mode = 'free'
		state = 'Waiting'
		if config.lastState == 'rpi booted'
			state = config.lastState
		if config.lastState == 'testing finished with error'
			state = config.lastState
	else
		mode = 'testing'
		state = config.lastState #fsm.current_state_name
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

	console.log 'Got /ping request, mode is ' + mode

	response =
		resp: 'ok'
		mode: mode
		state: state
		started: startTime
		now: Date.now()

	res.json response

# tests need this: jenkins will trigger this
app.get '/start', (req, res) ->
	console.log 'Got Start testing request from: '  +  req.ip

	config.appName = req.query.app
	config.img.appId = req.query.appId
	config.img.network = req.query.net
	config.img.uiHost = req.query.uiHost
	config.img.apiHost = req.query.apiHost
	config.credentials.email = req.query.username
	config.credentials.password = req.query.password

	console.log 'config: ' + config.img

	if fsm.current_state_name != 'Waiting'
		console.log 'Test in progress: [STATE] = ' + fsm.current_state_name
		mode = 'testing'
		state = config.lastState #fsm.current_state_name
	else
		console.log 'Starting test'
		mode = 'free'
		state = 'started'
		config.lastState = 'started'
		startTest(config)

	response =
		resp: 'ok'
		mode: mode
		state: state
		started: startTime
		now: Date.now()

	res.json response

startTest = (testData) ->
	console.log 'data.img: ' + testData.img
	console.log 'Starting FSM'
	startTime = Date.now()
	fsm.config.initial_state = 'Initialize'
	fsm.current_state_name = 'Initialize'
	fsm.current_data = testData
	fsm.start()

console.log 'Starting Server'
app.listen(process.env.PORT or 8080)
