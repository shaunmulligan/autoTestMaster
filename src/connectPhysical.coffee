Gpio = require 'pi-pins'
sdCardConn = Gpio.connect(17)
usbConn = Gpio.connect(18)
slaveConn = Gpio.connect(27)

exports.connectUsb = ->
	usbConn.mode('high')
	# SD card should always be disconnected if USB side is connected
	sdCardConn.mode('low')

exports.connectSd = ->
	usbConn.mode('low')
	sdCardConn.mode('high')

exports.powerSlave = ->
	usbConn.mode('low')
	sdCardConn.mode('high')
	slaveConn.mode('high')

exports.allOff = ->
	usbConn.mode('low')
	sdCardConn.mode('low')
	slaveConn.mode('low')
