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
bunyan = require 'bunyan'

logLevel = process.env.LOG_LEVEL or 'info'
logSettings =
	name: 'stateMachine'
	level: logLevel
	streams: [
		{
				type: 'rotating-file',
				path: '/data/stateMachine.log',
				period: '1d',	 # daily rotation
				count: 3,			 # keep 3 back copies
				level: 'debug'
		},
		{
			level: logLevel,
			stream: process.stdout
		}
	]
log = bunyan.createLogger logSettings

#should get this value from API
expectedImgSize = 1400.0
scanner = null
#probably should break these out into a utils module
removeAllDevices = (uuids) ->
	#TODO: rather use Promise.map([ 'a', 'b', 'c' ], resin.models.device.remove)
	#this only resolves the promise all mapped promises resolve
	return Promise.all(uuids.map(resin.models.device.remove))

shouldPollApp = true
# this is a hack
pollApp = ->
	return resin.models.device.getAllByApplication(config.appName)
	.then (devices) ->
		if !_.isEmpty(devices) and !_.isUndefined(devices[0]?.uuid)
			return devices[0]?.uuid
		if shouldPollApp
			log.info 'polling App for new device...'
			Promise.delay(3000).then(pollApp)
	.cancellable()

pollDevice = (uuid, expected, retries = 60) ->
	resin.models.device.get(uuid).then (device) ->
		if _.isMatch(device, expected)
			return device

		if retries is 0
			throw new Error('Timeout!')

		log.info 'Polling device...' + Object.keys(expected)[0]
		return Promise.delay(3000).then ->
			pollDevice(uuid, expected, retries - 1)

class AutoTester extends NodeState
	states:
		Initialize:
			#Check internet and connection to api, then login to resin
			Enter: (data) ->
				#Initialise the Internet connectivity tester
				DeviceConn.init()
				log.info '[STATE] ' + @current_state_name
				physicalMedia.allOff()
				DeviceConn.hasInternet()
				.then (isConnected) =>
					if isConnected
						log.info 'connected to Internet'
						#login to resin
						resin.auth.login(config.credentials)
						.then =>
							log.info 'logged as:' + config.credentials.email
							config.lastEvent = 'logged in'
							#clean up all devices before we start
							# TODO: check that application exists:
							resin.models.device.getAllByApplication(config.appName)
							.then (devices) =>
								uuids = (device.uuid for device in devices)
								removeAllDevices(uuids)
								.then (results) =>
									failures = (result for result in results when result isnt 'OK')
									log.debug 'device remove failures:' + failures
									if _.isEmpty(failures)
										log.info 'all devices have been removed from app'
										config.lastEvent = 'app is clear of devices'
										@goto 'DownloadImage', data
										# skip the download during testing
										#@goto 'MountMedia' , { fileSize: null }
									else
										error = 'failed to remove some devices'
										@goto 'ErrorState' , { error: error, state: @current_state_name }
								.catch (error) =>
									@goto 'ErrorState' , { error: error, state: @current_state_name }
						.catch (error) =>
							@goto 'ErrorState' , { error: error, state: @current_state_name }
					else
						error = 'No Internet Connectivity'
						@goto 'ErrorState' , { error: error, state: @current_state_name }

		DownloadImage:
			# Check connection to api and internet, then download .img with cli/sdk
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				@wait 10 * 60 * 1000 # timeout if a download takes longer than 10 minutes
				# TODO: switch resin.auth to promise base version
				resin.auth.isLoggedIn (error, isLoggedIn) =>
					if error?
						@goto 'ErrorState', { error: error, state: @current_state_name }

					if isLoggedIn
						params = data.img
						log.debug { params: params }
						resin.models.os.download(params)
						.then (stream) =>
							stream.pipe(fs.createWriteStream(config.img.pathToImg))
							log.info 'Downloading device OS for appID = ' + params.appId
							stream.on 'error', (err) =>
								@goto 'ErrorState', { error: err }
							stream.on 'end', =>
								stats = fs.statSync(config.img.pathToImg)
								fileSizeInMb = stats['size'] / 1000000.0
								log.info 'download size = ' + fileSizeInMb
								config.lastEvent = 'image was downloaded'
								if fileSizeInMb < expectedImgSize
									error = 'download is too small, something went wrong!'
									@goto 'ErrorState' , { error: error, state: @current_state_name }
								else
									@goto 'MountMedia', { fileSize: fileSizeInMb }
						.catch (error) =>
							@goto 'ErrorState' , { error: error, state: @current_state_name }
					else
						error = 'Not logged in to resin'
						@goto 'ErrorState' , { error: error, state: @current_state_name }

				WaitTimeout: (timeout, data) ->
					error = 'timedout while waiting for download'
					@goto 'ErrorState', { error: error, state: @current_state_name }

		MountMedia:
			# pull GPIO high so Media disk is connected to Master USB,but not slave
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				physicalMedia.allOff()
				scanner = new DrivelistScanner(interval: 1000, drives: [ ])
				physicalMedia.connectUsb()
				log.info 'Mounting Install Media'

				scanner.on 'add', (drives) =>
					log.info drives
					# TODO: emit event here: {event: mount-drive drive:drives.device}
					scanner.stop()
					@unwait()
					@goto 'WriteMedia', { drive: drives.device }

				@wait 10000 # timeout if media takes longer than 10s to mount

			WaitTimeout: (timeout, data) ->
				scanner.stop()
				error = 'timeout reached, unable to mount the USB media'
				@goto 'ErrorState', { error: error, state: fsm.current_state_name }

		WriteMedia:
			# Write to install media
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				log.info 'Writing to Install Media: ' + data.drive
				writer.writeImage config.img.pathToImg, {
					device: data.drive
					}, (state) ->
						log.debug { percentage_written: state.percentage }
					.then =>
						log.info('Done!')
						log.info config.img.pathToImg + ' was written to ' +	data.drive
						config.lastEvent = 'image was written'
						@goto 'EjectMedia'
					.catch (error) =>
						@goto 'ErrorState' , { error: error, state: fsm.current_state_name }

		EjectMedia:
			# Pull GPIO low so Media disk is disconnected from Master USB
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				log.info 'Ejecting install media'
				physicalMedia.allOff()
				@goto 'PlugMediaIntoSlaveDevice'

		PlugMediaIntoSlaveDevice:
			# Pull GPIO high so Media disk is now connected to slave ready to boot
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				log.info 'Inserting install media into device'
				physicalMedia.connectSd()
				@goto 'PowerSlaveDevice'

		PowerSlaveDevice:
			# apply power to slave, check that power is actually on, if it is
			# then go to successful test...lots could be done here to validate
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				#wait 30seconds for the power to be applied
				@wait 30000
				physicalMedia.powerSlaveWithBootMedia()
				# TODO: need to have a GPIO input to check that power actually applied
				@goto 'DeviceOnDashboard'

			WaitTimeout: (timeout, data) ->
				error = 'Power was never applied'
				@goto 'ErrorState', { error: error, state: fsm.current_state_name }

		DeviceOnDashboard:
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				#start a timer, timeout after 4 minutes of waiting
				pollApp().timeout(240000).then (uuid) =>
					log.info 'A device was found: ' + uuid
					config.lastEvent = 'rpi booted'
					# TODO: Need a more generic way of doing switch between devic-types
					if config.img.devType == 'nuc'
						@goto 'PostProvision' , { UUID: uuid }
					else
						@goto 'TestSuccess'
				.catch Promise.TimeoutError, (error) =>
					shouldPollApp = false
					@goto 'ErrorState', { error: error, state: @current_state_name }
				.catch (error) =>
					@goto 'ErrorState', { error: error, state: @current_state_name }

			WaitTimeout: (timeout, data) ->
				error = 'Device never showed up on dashboard'
				@goto 'ErrorState', { error: error, state: @current_state_name }

		# Flasher Types Only
		PostProvision:
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				@wait 10 * 60 * 1000, data

				pollDevice(data.UUID, provisioning_state: 'Post-Provisioning' )
				.then (device) =>
					log.debug device
					log.info 'Device is shutting down...'
					@goto 'UnmountBootMedia', data
				.catch (error) =>
					@goto 'ErrorState', { error: error, state: fsm.current_state_name }

			WaitTimeout: (timeout, data) ->
				@goto 'ErrorState' , { error: 'timeout error' }
		# Flasher Types Only
		UnmountBootMedia:
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				physicalMedia.unmountBootMedia()
				@goto 'PowerCycleSlave', data
		# Flasher Types Only
		PowerCycleSlave:
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				physicalMedia.allOff()
				log.info 'waiting for 5 sec'
				@wait 5 * 1000 , data

			WaitTimeout: (timeout, data) ->
				physicalMedia.powerSlave()
				@goto 'WaitForOnlineDevice' , data

		# Flasher Types Only
		WaitForOnlineDevice:
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				@wait 10 * 60 * 1000, data

				pollDevice(data.UUID, is_online: true )
				.then (device) =>
					log.debug device
					log.info 'Device came back online...'
					@goto 'TestSuccess', data
				.catch (error) =>
					@goto 'ErrorState', { error: error, state: @current_state_name }

			WaitTimeout: (timeout, data) ->
				@goto 'ErrorState' , { error: 'timeout error' }

		TestSuccess:
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				log.info 'Successfully provisioned Slave device'
				@goto 'Waiting'

		Waiting:
			#Wait for a Test to be started
			Enter: (data) ->
				log.info '[STATE] ' + @current_state_name
				# @stop()

		ErrorState:
			Enter: (data) ->
				#TODO: add this to config.error so that it is reflected in /jstatus
				# Should report which state had the error and what it was, then return
				# to initial state
				log.info '[STATE] ' + @current_state_name
				log.error 'Error occured in ' + data.state + ': ' + data.error
				config.lastEvent = 'testing finished with error'
				config.error = data.error
				@goto 'Waiting'

module.exports = AutoTester
