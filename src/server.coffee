express = require 'express'
AutoTester = require './main'

startTime = 0
data =
  uuid: ""
  log: null
  state: null
  error: ""
  timeout: false
  states: null
  token: process.env.TOKEN
  sTim: null
  Utoken: process.env.TOKEN
  appName: process.env.SLAVEAPP || 'rpiSlave'
  img:
    appId: process.env.SLAVE_APP_ID || 9155
    network: "ethernet"
    ssid: "Techspace"
    wifiKey: "cak-wy-rum"
    uiHost: "https://dashboard.resin.io"
    apiHost: "https://api.resin.io"
  credentials:
    username: process.env.USERNAME
    password: process.env.USER_PASS

app = express()
fsm = new AutoTester
  initial_data: data #pass in test data here
  initial_state: 'Waiting'


app.get '/status', (req, res) ->
  console.log "Got /status request"
  res.send(data.state)

app.get '/jstatus', (req, res) ->
  console.log "Got /jstatus request"
  resData =
    state: data.state
    error: data.error
    started: time
    now: Date.now()
  res.json( resData )

app.get '/tstatus', (req, res) ->
  console.log "Got /tstatus request"
  res.json( { timer: (data.sTim?) , timeout: data.Timeout } )

app.get '/uuid', (req, res) ->
  console.log "Got /uuid request"
  res.json( { uuid: data.uuid } )

# tests need this: jenkins will ping to check if device is online
app.get '/ping', (req, res) ->
  if !fsm.current_state_name? or fsm.current_state_name == 'Waiting'
    mode = "free"
    state = 'Waiting'
  else
    mode = "testing"
    state = fsm.current_state_name

  console.log "Got /ping request, mode is "+mode

  response =
    resp: "ok"
    mode: mode
    state: state
    started: startTime
    now: Date.now()

  res.json response

# tests need this: jenkins will trigger this
#/start?username=unicorn-tester@resin.io&password=12345678&appId=9322&app=alpine&net=ethernet&uiHost=https://dashboard.resin.io&apiHost=https://api.resin.io

app.get '/start', (req, res) ->
  console.log "Got Start testing request from: " + req.ip

  data.appName = req.query.app
  data.img.appId = req.query.appId
  data.img.network = req.query.net
  data.img.uiHost = req.query.uiHost
  data.img.apiHost = req.query.apiHost
  data.credentials.username = req.query.username
  data.credentials.password = req.query.password

  console.log 'data: '+data.img

  if fsm.current_state_name != 'Waiting'
    console.log 'Test in progress: [STATE] = '+fsm.current_state_name
    mode = 'testing'
  else
    console.log 'Starting test with default config'
    mode = 'free'
    startTest(data)

  response =
    resp: "ok"
    mode: mode
    state: fsm.current_state_name
    started: startTime
    now: Date.now()

  res.json response

app.get '/startdefault', (req, res) ->
  if fsm.current_state_name != 'Waiting'
    console.log 'Test in progress: [STATE] = '+fsm.current_state_name
    mode = 'testing'
  else
    console.log 'Starting test with default config'
    mode = 'free'
    startTest(data)

  response =
    resp: "ok"
    mode: mode
    state: fsm.current_state_name
    started: startTime
    now: Date.now()

  res.json response

startTest = (testData) ->
  console.log 'data.img: '+testData.img
  console.log 'Starting FSM'
  startTime = Date.now()
  fsm.config.initial_state = 'Initialize'
  fsm.current_state_name = 'Initialize'
  fsm.current_data = testData
  fsm.start()

console.log 'Starting Server'
app.listen(8080)
