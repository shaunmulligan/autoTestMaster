NodeState = require 'node-state'
DeviceConn = require 'netcheck'
resin = require 'resin-sdk'
_ = require 'lodash'
Promise = require 'bluebird'
fs = require 'fs'
physicalMedia = require './connectPhysical'
DrivelistScanner = require 'drivelist-scanner'
diskio = require 'diskio'
writer = require '../lib/writer'
config = require './config'

#probably should break these out into a utils module
removeAllDevices = (uuids) ->
	#TODO: rather use Promise.map([ 'a', 'b', 'c' ], resin.models.device.remove)
	#this only resolves the promise all mapped promises resolve
	return Promise.all(uuids.map(resin.models.device.remove))

awaitDevice = ->
	poll = ->
		setTimeout ->
			error = 'timedout while waiting for device to show on dashboard'
			return error
		, 24000

		resin.models.device.getAllByApplication(config.appName)
		.then (devices) ->
			if _.isEmpty(devices)
				console.log 'polling app'
				return Promise.delay(3000).then(poll)
			else
				return devices[0].uuid
		.catch (error) ->
			console.log 'error while polling for device: ' + error + ' . Trying again'
			return Promise.delay(3000).then(poll)

	poll().return()

class AutoTester extends NodeState
	states:
		Initialize:
			#Check internet and connection to api, then login to resin
			Enter: (data) ->
				fsm = this
				#Initialise the Internet connectivity tester
				DeviceConn.init()
				console.log '[STATE] ' + @current_state_name
				physicalMedia.allOff()
				DeviceConn.hasInternet()
					.then (isConnected) ->
						if isConnected
							console.log 'connected to Internet'
							#login to resin
							resin.auth.login(config.credentials)
							.then ->
								console.log 'logged as:' + config.credentials.email
								#emit event here: event: logged-in
								config.lastState = 'logged in'
								#clean up all devices before we start
								resin.models.device.getAllByApplication(config.appName)
								.then (devices) ->
									uuids = (device.uuid for device in devices)
									removeAllDevices(uuids)
									.then (results) ->
										failures = (result for result in results when result isnt 'OK')
										console.log 'device remove failures:' + failures
										if _.isEmpty(failures)
											console.log 'all devices have been removed'
											config.lastState = 'app is clear of devices'
											fsm.goto 'DownloadImage', data
										else
											error = 'failed to remove some devices'
											fsm.goto 'ErrorState' , { error: error, state: fsm.current_state_name }
									.catch (error) ->
										fsm.goto 'ErrorState' , { error: error, state: fsm.current_state_name }
							.catch (error) ->
								fsm.goto 'ErrorState' , { error: error, state: fsm.current_state_name }
						else
							error = 'No Internet Connectivity'
							fsm.goto 'ErrorState' , { error: error, state: fsm.current_state_name }

		DownloadImage:
			# Check connection to api and internet, then download .img with cli/sdk
			Enter: (data) ->
				fsm = this
				console.log '[STATE] ' + @current_state_name
				@wait 200000 # timeout if a download takes longer than 20 minutes
				resin.auth.isLoggedIn (error, isLoggedIn) ->
					if error?
						fsm.goto 'ErrorState', { error: error, state: fsm.current_state_name }

					if isLoggedIn
						resin.auth.whoami()
							.then (username) ->
								if (!username)
									console.log('I\'m not logged in!')
									#need to switch to using a promise .catch here
								else
									console.log('Logged in as:', username)
						params = data.img
						console.log 'params: ' + params.network + ',' + params.ssid
						resin.models.os.download(params)
						.then (stream) ->
							stream.pipe(fs.createWriteStream(config.img.pathToImg))
							console.log 'Downloading device OS for appID = ' + params.appId
							stream.on 'error', (err) ->
								fsm.goto 'ErrorState', { error: err }
							stream.on 'end', ->
								stats = fs.statSync(config.img.pathToImg)
								fileSizeInMb = stats['size'] / 1000000.0
								console.log 'download size = ' + fileSizeInMb
								config.lastState = 'image was downloaded'
								#emit event here: event: image-downloaded size: fileSizeInMb
								fsm.goto 'MountMedia', { fileSize: fileSizeInMb }
						.catch (error) ->
							fsm.goto 'ErrorState' , { error: error, state: fsm.current_state_name }
					else
						error = 'Not logged in to resin'
						fsm.goto 'ErrorState' , { error: error, state: fsm.current_state_name }

				WaitTimeout: (timeout, data) ->
					fsm = this
					error = 'timedout while waiting for download'
					@goto 'ErrorState', { error: error, state: fsm.current_state_name }

		MountMedia:
			# pull GPIO high so Media disk is connected to Master USB
			Enter: (data) ->
				fsm = this
				console.log '[STATE] ' + @current_state_name
				physicalMedia.allOff()
				@wait 5000 # timeout if media takes too long to mount

				scanner = new DrivelistScanner(interval: 1000, drives: [ ])
				physicalMedia.connectUsb()
				console.log 'Mounting Install Media'

				scanner.on 'add', (drives) ->
					console.log drives
					#emit event here: {event: mount-drive drive:drives.device}
					scanner.stop()
					fsm.unwait()
					fsm.goto 'WriteMedia', { drive: drives.device }

			WaitTimeout: (timeout, data) ->
				fsm = this
				error = 'Was unable to mount the USB media'
				@goto 'ErrorState', { error: error, state: fsm.current_state_name }

		WriteMedia:
			# Write to install media
			Enter: (data) ->
				fsm = this
				console.log '[STATE] ' + @current_state_name
				console.log 'Writing to Install Media: ' + data.drive
				writer.writeImage config.img.pathToImg, {
					device: data.drive
					}, (state) ->
						console.log state.percentage
						#can also stream write progress from here
					.then ->
						console.log('Done!')
						console.log config.img.pathToImg + ' was written to ' +	data.drive
						config.lastState = 'image was written'
						#emit event here: event: image-written-to-drive
						fsm.goto 'EjectMedia'
					.catch (error) ->
						fsm.goto 'ErrorState' , { error: error, state: fsm.current_state_name }

		EjectMedia:
			# Pull GPIO low so Media disk is disconnected from Master USB
			Enter: (data) ->
				console.log '[STATE] ' + @current_state_name
				console.log 'Ejecting install media'
				physicalMedia.allOff()
				#emit event here: event: drive-ejected
				@goto 'PlugMediaIntoSlaveDevice'

		PlugMediaIntoSlaveDevice:
			# Pull GPIO high so Media disk is now connected to slave ready to boot
			Enter: (data) ->
				console.log '[STATE] ' + @current_state_name
				console.log 'Inserting install media into device'
				physicalMedia.connectSd()
				@goto 'PowerSlaveDevice'

		PowerSlaveDevice:
			# apply power to slave, check that power is actually on, if it is
			# then go to successful test...lots could be done here to validate
			Enter: (data) ->
				fsm = this
				console.log '[STATE] ' + @current_state_name
				#wait 30seconds for the power to be applied
				@wait 30000
				physicalMedia.powerSlave()
				#emit event here: event: slave-powered-up
				# TODO: need to have a GPIO input to check that power actually applied
				@goto 'DeviceOnDashboard'

			WaitTimeout: (timeout, data) ->
				fsm = this
				error = 'Power was never applied'
				@goto 'ErrorState', { error: error, state: fsm.current_state_name }

		DeviceOnDashboard:
			# jenkins should wait about 2-3 minute for device to pop up in dash
			Enter: (data) ->
				fsm = this
				console.log '[STATE] ' + @current_state_name
				#start a timer, timeout after 4 minutes of waiting
				# @wait 240000

				awaitDevice()
				.then (uuid) ->
					console.log 'A device just came online: ' + uuid
					config.lastState = 'rpi booted'
					fsm.goto 'TestSuccess'
				.catch (error) ->
					fsm.goto 'ErrorState', { error: error, state: fsm.current_state_name }

			WaitTimeout: (timeout, data) ->
				fsm = this
				error = 'Device never showed up on dashboard'
				@goto 'ErrorState', { error: error, state: fsm.current_state_name }

		TestSuccess:
			Enter: (data) ->
				console.log '[STATE] ' + @current_state_name
				console.log 'Successfully provisioned Slave device'
				#emit event here: event: test-success
				@goto 'Waiting'

		Waiting:
			#Wait for a Test to be started
			Enter: (data) ->
				fsm = this
				console.log '[STATE] ' + @current_state_name
				#emit event here: event: waiting-for-test
				# @stop()

		ErrorState:
			Enter: (data) ->
				#TODO: add this to config.error so that it is reflected in /jstatus
				# Should report which state had the error and what it was, then return
				# to initial state
				console.log '[STATE] ' + @current_state_name
				console.log 'Error occured in ' + data.state + ': ' + data.error
				config.lastState = 'testing finished with error'
				#emit event here: event: error error:data.error
				@goto 'Waiting'

module.exports = AutoTester
