PROGRAM_NAME='common'
#DEFINE common // Common and basic functions
/*
=== [Description] =============================================================
Common stuff library every programmer should use in all projects.

Handles:
- Global master device dvMaster for system startup event
- Standard timelines definitions
- boot_times: Did the controller reboot at some time?
- blink variable, use for common button feedback etc.
- Some ASCII char constants: STX, rtc.
- Logging and log levels

=== [Settings] ================================================================
None

=== [Requirements] ============================================================
None

=== [Compile switches] ========================================================
External blink variable and controlling:
#DEFINE common_noblink

=== [Example snippet] =========================================================
# Attach to a timeline:



=== [Change log] ==============================================================
2019-10-11 Multistate activity
2022-03-09 Move activity into _panel.axi
2023-10-31 Stand alone release for community
           Reduced to only really useful stuff

=== [TO-DOs] ==================================================================

*/

DEFINE_DEVICE
dvMaster	=	0:1:0

DEFINE_CONSTANT
// Timelines
LONG TL_Blink = 510
LONG TL_01Second = 511
LONG TL_02Second = 512
LONG TL_05Second = 513
LONG TL_1Second = 514
LONG TL_5Second = 515
LONG TL_10Second = 516
LONG TL_30Second = 517
LONG TL_1Minute = 518
LONG TL_5Minute = 519
LONG TL_10Minute = 520


LONG _TL_Blink[]    = {   750}
LONG _TL_01Second[] = {   100}
LONG _TL_02Second[] = {   200}
LONG _TL_05Second[] = {   500}
LONG _TL_1Second[]  = {  1000}
LONG _TL_5Second[]  = {  5000}
LONG _TL_10Second[] = { 10000}
LONG _TL_30Second[] = { 30000}
LONG _TL_1Minute[]  = { 60000}
LONG _TL_5Minute[]  = {300000}
LONG _TL_10Minute[] = {600000}


// Remember boot times
INTEGER boot_record_count = 128

// Constants
CHAR SOH = $01
CHAR STX = $02
CHAR ETX = $03
CHAR ACK = $06
CHAR NAK = $15
CHAR ESC = $1B

// Log levels/categories
INTEGER logging_default = 0           // Standard/undefined, better strictly define a level
INTEGER logging_info = 1              // Informative
INTEGER logging_error = 2             // Errors
INTEGER logging_warning = 3           // Warnings
INTEGER logging_init = 4              // Information during inits
INTEGER logging_rx = 5                // Receiving raw data or related
INTEGER logging_tx = 6                // Sending raw data or related
INTEGER logging_debug = 7             // Verbgose debug info
INTEGER _logging_type_last = 7        // LAST ID
CHAR _logging_typenames[_logging_type_last+1][4] = {'???','INFO','ERR','WARN','INIT','RX','TX','###'}  // Prefixes for string outputs

INTEGER log0wrap_maxlength = 180 // May allowed line length for SEND_STRING 0
INTEGER log0wrap_maxlines = 16 // Max number of lines to print. Don't print too much data to not flood the console.

DEFINE_VARIABLE
VOLATILE INTEGER system_online // True after master online event

#IF_NOT_DEFINED common_noblink
VOLATILE INTEGER blink = 0
#END_IF

VOLATILE INTEGER no_blink = 0  // Disable global blink by variable
VOLATILE IP_ADDRESS_STRUCT my_ip_config

PERSISTENT CHAR boot_times[boot_record_count][17]
PERSISTENT INTEGER boot_times_lastindex

// Enhancement for SEND_STRING 0, ...
// May be redirected to a logging system
DEFINE_FUNCTION log0(CHAR msg[]) {
	// Forward to wrapped console output
	log0_wraphandler(msg)
}

// Prints to console. Wraps long lines to not be truncated.
DEFINE_FUNCTION log0_wraphandler(CHAR msg[]) {
	STACK_VAR INTEGER line_cnt
	STACK_VAR CHAR chunk[log0wrap_maxlength]

	if (LENGTH_STRING(msg)<=log0wrap_maxlength) {
		// Small message. Just print.
		SEND_STRING 0,"msg"
		return;
	}
	
	// Handle longer log message
	for(line_cnt=1;LENGTH_STRING(msg) and line_cnt<log0wrap_maxlines; line_cnt++) {
		chunk = GET_BUFFER_STRING(msg,log0wrap_maxlength)

		if (line_cnt==1)
			SEND_STRING 0, "chunk"
		else
			SEND_STRING 0, "'...',chunk"
	}
}

DEFINE_FUNCTION log(INTEGER module_id, INTEGER logtype, CHAR msg[]) {
	log0("_logging_typenames[logtype+1],' [',ITOA(module_id),']: ', msg")
}

DEFINE_FUNCTION make_dev_real(DEV writeable_device_var) {
	if (writeable_device_var.system == 0) {
		writeable_device_var.system = GET_SYSTEM_NUMBER()
	}
}

DEFINE_EVENT
DATA_EVENT[dvMaster] {
	ONLINE: {
		log0("'=== Master-Device now online. No variable changes until now allowed.'")
		system_online = 1
		
		// Record boot time
		boot_times_lastindex = (boot_times_lastindex % boot_record_count) + 1
		boot_times[boot_times_lastindex] = "DATE,' ',TIME"

		// Get my ip config
		GET_IP_ADDRESS(dvMaster, my_ip_config)
		
		log0('Creating timelines...')
		TIMELINE_CREATE(TL_Blink,    _TL_Blink,    1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_01Second, _TL_01Second, 1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_02Second, _TL_02Second, 1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_05Second, _TL_05Second, 1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_1Second,  _TL_1Second,  1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_5Second,  _TL_5Second,  1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_10Second, _TL_10Second, 1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_30Second, _TL_30Second, 1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_1Minute,  _TL_1Minute,  1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_5Minute,  _TL_5Minute,  1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
		TIMELINE_CREATE(TL_10Minute, _TL_10Minute, 1, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
	}
}

TIMELINE_EVENT[TL_Blink] {
#IF_NOT_DEFINED common_noblink
	if (no_blink) {
		blink = 1
	} else {
		blink = !blink
	}
#END_IF
}
