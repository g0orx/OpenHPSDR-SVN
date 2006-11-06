rem @echo off 
rem initialize i2c device on the fpga board 
rem wolfson init   
rem		- 34 00 25 - left justified, master, 48 khz 
rem		- 34 02 00 - 16 bit samples 
rem TLV320 init 
rem 	- 36 1E 00 - Reset chip
rem 	- 36 12 01 - set digital interface active
rem 	- 36 08 15 - D/A on, mic input, mic 20dB boost
rem 	- 36 0C 00 - All chip power on
rem 	- 36 0E 01 - Slave, 16 bit, Left Justified
rem		- 36 10 40 - Clock/2, 48k, Normal mode
rem		- 36 0A 00 - turn D/A mute off

i2c-cmd 34 00 25
sleep 1 
i2c-cmd 34 02 00
sleep 1
i2c-cmd 36 1e 00
sleep 1 
i2c-cmd 36 12 01
sleep 1 
i2c-cmd 36 08 15
sleep 1 
i2c-cmd 36 0c 00
sleep 1 
i2c-cmd 36 0e 01
sleep 1 
i2c-cmd 36 10 40
sleep 1 
i2c-cmd 36 0a 00
