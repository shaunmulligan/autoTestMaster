NodeState = require 'node-state'
DeviceConn = require 'netcheck'
resin = require 'resin-sdk'
fs = require 'fs'
physicalMedia = require './connectPhysical'
DrivelistScanner = require 'drivelist-scanner'
diskio = require 'diskio'
writer = require '../lib/writer'
config = require './config'

class AutoTester extends NodeState
  states:
    Initialize:
      #Check internet and connection to api, then login to resin
      Enter: (data) ->
        fsm = this
        #Initialise the Internet connectivity tester
        DeviceConn.init()
        console.log '[STATE] '+@current_state_name
        physicalMedia.allOff()
        DeviceConn.hasInternet()
          .then (isConnected) ->
            if isConnected
              console.log 'connected to Internet'
              #TODO: login here with stuff from data object
              #login to resin
              resin.auth.loginWithToken config.token, (error) ->
                if error?
                  fsm.goto 'ErrorState' , {error: error}
                else
                  console.log 'logged into resin.io'
                  fsm.goto 'DownloadImage', data
            else
              error = 'No Internet Connectivity'
              fsm.goto 'ErrorState' , {error: error}

    DownloadImage:
      # Check connection to api and internet, then download .img with cli/sdk
      Enter: (data) ->
        fsm = this
        console.log '[STATE] '+@current_state_name
        console.log 'data: '+data.img
        @wait 200000 # timeout if a download takes longer than 20 minutes
        resin.auth.isLoggedIn (error, isLoggedIn) ->
          if error?
            fsm.goto 'ErrorState', {error: error}

          if isLoggedIn
            resin.auth.whoami()
              .then (username) ->
                if (!username)
                  console.log('I\'m not logged in!')
                else
                  console.log('Logged in as:', username)
            params = data.img
            console.log 'params: '+params
            resin.models.os.download(params).then (stream) ->
              stream.pipe(fs.createWriteStream(config.img.pathToImg))
              console.log 'Downloading device OS for appID = '+params.appId
              stream.on 'error', (err) ->
                fsm.goto 'ErrorState', {error: err}
              stream.on 'end', ->
                stats = fs.statSync(config.img.pathToImg)
                fileSizeInMb = stats['size']/1000000.0
                console.log 'download size = '+ fileSizeInMb
                fsm.goto 'MountMedia', { fileSize: fileSizeInMb }
          else
            error = 'Not logged in to resin'
            fsm.goto 'ErrorState' , {error: error}

        WaitTimeout: (timeout, data) ->
          error = 'timedout while waiting for download'
          @goto 'ErrorState', {error: error}

    MountMedia:
      # pull GPIO high so Media disk is connected to Master USB
      Enter: (data) ->
        fsm = this
        console.log '[STATE] '+@current_state_name
        physicalMedia.allOff()
        @wait 3000 # timeout if media takes too long to mount

        scanner = new DrivelistScanner(interval: 1000, drives: [ ])
        physicalMedia.connectUsb()
        console.log 'Mounting Install Media'

        scanner.on 'add', (drives) ->
          console.log drives
          scanner.stop()
          fsm.unwait()
          fsm.goto 'WriteMedia', {drive: drives.device}

      WaitTimeout: (timeout, data) ->
        error = 'Was unable to mount the USB media'
        @goto 'ErrorState', {error: error}

    WriteMedia:
      # Write to install media
      Enter: (data) ->
        fsm = this
        console.log '[STATE] '+@current_state_name
        console.log 'Writing to Install Media: '+data.drive
        writer.writeImage config.img.pathToImg, {
          device: data.drive
          }, (state) ->
            console.log state.percentage
          .then ->
            console.log('Done!')
            console.log config.img.pathToImg+' was written to '+ data.drive
            fsm.goto 'EjectMedia'

    EjectMedia:
      # Pull GPIO low so Media disk is disconnected from Master USB
      Enter: (data) ->
        console.log '[STATE] '+@current_state_name
        console.log 'Ejecting install media'
        physicalMedia.allOff()
        @goto 'PlugMediaIntoSlaveDevice'

    PlugMediaIntoSlaveDevice:
      # Pull GPIO high so Media disk is now connected to slave ready to boot
      Enter: (data) ->
        console.log '[STATE] '+@current_state_name
        console.log 'Inserting install media into device'
        physicalMedia.connectSd()
        @goto 'PowerSlaveDevice'

    PowerSlaveDevice:
      # apply power to slave, check that power is actually on, if it is
      # then go to successful test...lots could be done here to validate
      # jenkins should wait about 2-3 minute for device to pop up in dash
      Enter: (data) ->
        console.log '[STATE] '+@current_state_name
        physicalMedia.powerSlave()
        # TODO: need to have a GPIO input to check that power is actually there
        @goto 'TestSuccess'

    TestSuccess:
      Enter: (data) ->
        console.log '[STATE] '+@current_state_name
        console.log 'Successfully provisioned Slave device'
        @goto 'Waiting'

    Waiting:
      #Wait for a Test to be started
      Enter: (data) ->
        fsm = this
        console.log '[STATE] '+@current_state_name
        # @stop()

    ErrorState:
      Enter: (data) ->
        # Should report which state had the error and what it was, then return
        # to initial state
        console.log '[STATE] '+@current_state_name
        console.log 'Error has occured: ' + data.error
        @goto 'Waiting'

# Server Waits here for a /start request from Jenkins or pubnub
# fsm = new AutoTester
#   initial_data: {} #pass in test data here
#   initial_state: 'Initialize'

# #Initialise the Internet connectivity tester
# DeviceConn.init()
# console.log 'Starting FSM'
# fsm.start()
module.exports = AutoTester
