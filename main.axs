PROGRAM_NAME='main'

DEFINE_DEVICE
//For ipdev classic mode:
dvIPConnection1 = 0:5:0
dvIPConnection2 = 0:6:0

dvPanel1 = 10001:1:1


DEFINE_VARIABLE
//For dynamic ipdev mode:
//VOLATILE DEV dvIPConnection1
//VOLATILE DEV dvIPConnection2

#INCLUDE 'common.axi' // Very common stuff for all your projects

//#DEFINE ip_manager_variable_devs
#INCLUDE 'ip_manager.axi'


DEFINE_EVENT

DATA_EVENT[dvMaster] { // Startup event.
	ONLINE: {
		// Permanent connection. Declare and forget.
		ip_create_tcp(dvIPConnection1, 'My device', '192.168.51.50', 5000, 1) // 1=Immediately connect and reconnect on disconnect events

		// Manual connection. Requires explicit connecting and closing.
		ip_create_tcp(dvIPConnection2, 'My device 2', '192.168.51.50', 5001, 0) // 0=Don't connect or reconnect
	}
}

BUTTON_EVENT[dvPanel1, 1]
{
	PUSH: {
		ip_close(dvIPConnection2) // Disconnect now and don't reconnect automatically again
	}
}

BUTTON_EVENT[dvPanel1, 2]
{
	PUSH: {
		ip_open(dvIPConnection2,1) // Connect now and reconnect automatically
	}
}

DATA_EVENT[dvIPConnection1] {
	ONLINE: {
		log0('Connection1 established!')
		SEND_STRING dvIPConnection1, "'Hi from AMX!',$0D,$0A"
	}
	OFFLINE: {
		log0('Connection1 closed!')
	}
	ONERROR: {
		log0('Connection1 error!')
	}
	STRING: {
		log0("'Connection1 received string:',DATA.TEXT")
	}
}

DATA_EVENT[dvIPConnection2] {
	ONLINE: {
		log0('Connection2 established!')
		SEND_STRING dvIPConnection2, "'Hi from AMX!',$0D"
	}
	OFFLINE: {
		log0('Connection2 closed!')
	}
	ONERROR: {
		log0('Connection2 error!')
	}
	STRING: {
		log0("'Connection2 received string:',DATA.TEXT")
	}
}
