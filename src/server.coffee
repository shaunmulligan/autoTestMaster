express = require 'express'
AutoTester = require './stateMachine'
config = require './config'

startTime = 0

app = express()
fsm = new AutoTester
	initial_data: config #pass the default test config in here
	initial_state: 'Waiting'

# Don't think this is used
app.get '/status', (req, res) ->
	console.log 'Got /status request'
	res.send(config.state)

app.get '/jstatus', (req, res) ->
	console.log 'Got /jstatus request'
	if !fsm.current_state_name? or fsm.current_state_name == 'Waiting'
		mode = 'free'
		state = 'Waiting'
	else
		mode = 'testing'
		state = fsm.current_state_name
	resData =
		state: state
		error: config.error
		started: startTime
		now: Date.now()
	res.json( resData )

# Don't think this is used
app.get '/tstatus', (req, res) ->
	console.log 'Got /tstatus request'
	res.json( { timer: (config.sTim?) , timeout: config.Timeout } )

# Don't think this is used
app.get '/uuid', (req, res) ->
	console.log 'Got /uuid request'
	res.json( { uuid: config.uuid } )

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
	else
		console.log 'Starting test'
		mode = 'free'
		startTest(config)

	response =
		resp: 'ok'
		mode: mode
		state: fsm.current_state_name
		started: startTime
		now: Date.now()

	res.json response

app.get '/startdefault', (req, res) ->
	#this currently will uses the config from previous test :/
	if fsm.current_state_name != 'Waiting'
		console.log 'Test in progress: [STATE] = ' + fsm.current_state_name
		mode = 'testing'
	else
		console.log 'Starting test with default config'
		mode = 'free'
		startTest(config)

	response =
		resp: 'ok'
		mode: mode
		state: fsm.current_state_name
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
