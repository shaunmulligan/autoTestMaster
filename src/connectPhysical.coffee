Gpio = require 'pi-pins'
sdCardConn = Gpio.connect(17)
usbConn = Gpio.connect(18)
slaveConn = Gpio.connect(27)

sdCardConn.mode('out')
usbConn.mode('out')
slaveConn.mode('out')

exports.connectUsb = ->
	usbConn.value(1)
	# SD card should always be disconnected if USB side is connected
	sdCardConn.value(0)

exports.connectSd = ->
	usbConn.value(0)
	sdCardConn.value(1)

exports.powerSlaveWithBootMedia = ->
	usbConn.value(0)
	sdCardConn.value(1)
	slaveConn.value(1)

exports.powerSlave = ->
	usbConn.value(0)
	sdCardConn.value(0)
	slaveConn.value(1)

exports.unmountBootMedia = ->
	usbConn.value(0)
	sdCardConn.value(0)
	slaveConn.value(1)

exports.allOff = ->
	usbConn.value(0)
	sdCardConn.value(0)
	slaveConn.value(0)
