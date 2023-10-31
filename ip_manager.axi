PROGRAM_NAME='ip_manager'
#DEFINE ip_manager
/*
=== [Description] =============================================================
Supports easy to setup IP connections with auto reconnect features (for TCP, TLS, SSH)

See function definition below for usage
TCP-Client: ip_create_tcp
UDP-2Way: ip_create_udp
SSH-Client: ip_create_ssh
TLS_Client: ip_create_tls
UDP-Server: ip_create_server_udp
TCP-Server: ip_create_server_tcp


# ip_manager_variable_devs mode
Handling dynamic IP communication as native devices without conflicts.
No more enumerating local ports. So your code can anywhere grab the next one.
If you're using this file in variable mode, don't define local ports anywhere.


=== [Settings (debugger)] ================================================================
VOLATILE ip_manager_run     Temporarily close and disable all connections
PERSISTENT INTEGER ip_manager_retry_interval = 10
PERSISTENT INTEGER ip_manager_retry_long_interval = 60
PERSISTENT INTEGER ip_manager_retry_long_after = 10
PERSISTENT INTEGER ip_manager_disconnect_before_connect = 1


=== [Requirements] ============================================================
common.axi

=== [Compile switches] ========================================================
#DEFINE ip_manager_variable_devs // Using variable device enumerating via DEFINE_VARIABLE. Cool but breaks CREATE_BUFFER.
#DEFINE ip_manager_no_panel // Don't use panel variable and functions

=== [Example snippet] =========================================================
#INCLUDE 'common.axi'
#INCLUDE 'ip_manager.axi'

//For classic mode:
DEFINE_DEVICE
dvIPConnection1 = 0:5:0

//For dynamic mode:
//DEFINE_VARIABLE
//VOLATILE DEV dvIPConnection1

DEFINE_EVENT

DATA_EVENT[dvMaster] { // Startup event.
	ONLINE: {
		ip_create_tcp(dvIPConnection1, 'My device', '192.168.51.10', 5000, 1)
	}
}

=== [Change log] ==============================================================
2019-08-06 Birthday. IP-Manager is third generation attempt.
2019-10-01 Add UDP Server
2019-10-08 dev rebuild warning
2019-11-05 ip_manager_constant_devs
2020-01-15 tcp_server
2020-02-18 Connection status feedback
2021-01-27 Soft timesouts (ip_set_rx_timeout)
2023-10-31 Stand alone release for community
           Inverted to ip_manager_variable_devs
					 Commented out panel integration for IP connection feedback

=== [TO-DOs] ==================================================================

critical: Rebuild_events does not affect device-events in modules?
use _ip_errorcode_description()
check for hangs in ip.state, soft_timeouts

===============================================================================

*/

#IF_DEFINED ip_manager_variable_devs
	#WARN 'INFO: ip_manager is in variable dev mode'
#ELSE
	#WARN 'INFO: ip_manager is in standard constant dev mode'
#END_IF

/*
#IF_DEFINED ip_manager_no_panel
	#WARN 'panel functions disabled in ip_manager'
#END_IF
*/

DEFINE_CONSTANT
INTEGER _ip_connections_max = 64
INTEGER _ip_type_tcp = 1
INTEGER _ip_type_udp = 2
INTEGER _ip_type_ssh = 3
INTEGER _ip_type_server_udp = 4
INTEGER _ip_type_server_tcp = 5
INTEGER _ip_type_tls = 6

#IF_DEFINED ip_manager_variable_devs
INTEGER _ip_first_local_port = 10
INTEGER _ip_manager_buffer_size = 1024
#END_IF

INTEGER _ip_manager_max_str = 64

INTEGER ip_state_connected = 1
INTEGER ip_state_connecting = 2
INTEGER ip_state_closed = 3
INTEGER ip_state_closing = 4
INTEGER ip_state_listening = 5

/*
#IF_NOT_DEFINED ip_manager_no_panel
INTEGER fbstatus_mode_off = 0
INTEGER fbstatus_mode_channel = 1
INTEGER fbstatus_mode_multistate = 2

INTEGER fbstatus_unknown = 0
INTEGER fbstatus_offline = 1
INTEGER fbstatus_online = 2
INTEGER fbstatus_deactivated = 3
INTEGER fbstatus_listening = 4
INTEGER fbstatus_connecting = 5
#END_IF
*/

DEFINE_TYPE
STRUCT ip_dev_data {
	CHAR name[_ip_manager_max_str]
	INTEGER ip_type
	
	CHAR remotehost[_ip_manager_max_str]
	INTEGER port

	INTEGER state

	INTEGER reconnect
	INTEGER connect

	INTEGER countdown
	INTEGER last_rx_secs
	INTEGER no_rx_timeout
	
	INTEGER unsuccessful_connect_count
	
	// ip_type == ip_type_ssh:
	CHAR ssh_user[_ip_manager_max_str]
	CHAR ssh_password[_ip_manager_max_str]

/*
#IF_NOT_DEFINED ip_manager_no_panel
	INTEGER fbstatus_mode
	INTEGER fbstatus
	INTEGER fbbtn_addr
#END_IF
*/
}

DEFINE_VARIABLE
VOLATILE INTEGER _ip_manager_myid

VOLATILE DEV ipdevs[_ip_connections_max]
VOLATILE ip_dev_data _ipdevs_data[_ip_connections_max]
VOLATILE INTEGER _ipdevs_last

// Map dev-port to index of ipdevs[]
VOLATILE INTEGER _ip_manager_port_to_devindex[256]

VOLATILE INTEGER ip_manager_run
PERSISTENT INTEGER ip_manager_retry_interval = 10
PERSISTENT INTEGER ip_manager_retry_long_interval = 60
PERSISTENT INTEGER ip_manager_retry_long_after = 10
PERSISTENT INTEGER ip_manager_disconnect_before_connect = 1 // For safety reasons. Throws error "Already disconnected"


DEFINE_FUNCTION INTEGER _ipdev_to_index(DEV ipdev) {
	if (ipdev.number != 0)
		return 0;
	
#IF_DEFINED ip_manager_variable_devs
	if (ipdev.port < _ip_first_local_port)
		return 0;
	
	return ipdev.port-_ip_first_local_port+1;
#ELSE
	return _ip_manager_port_to_devindex[ipdev.port];
#END_IF
}


// Init devices
DEFINE_FUNCTION INTEGER ip_create_tcp(DEV ipDEV, CHAR name[_ip_manager_max_str], CHAR remotehost[_ip_manager_max_str], INTEGER remoteport, INTEGER auto_connect) {
	STACK_VAR INTEGER newdev
	
	newdev = _ip_create_device(ipDEV)
	
	_ipdevs_data[newdev].name = name
	_ipdevs_data[newdev].ip_type = _ip_type_tcp
	_ipdevs_data[newdev].remotehost = remotehost
	_ipdevs_data[newdev].port = remoteport

	_ipdevs_data[newdev].connect = auto_connect
	_ipdevs_data[newdev].reconnect = auto_connect

	return newdev;
}

DEFINE_FUNCTION INTEGER ip_create_tls(DEV ipDEV, CHAR name[_ip_manager_max_str], CHAR remotehost[_ip_manager_max_str], INTEGER remoteport, INTEGER auto_connect) {
	STACK_VAR INTEGER newdev
	
	newdev = _ip_create_device(ipDEV)
	
	_ipdevs_data[newdev].name = name
	_ipdevs_data[newdev].ip_type = _ip_type_tls
	_ipdevs_data[newdev].remotehost = remotehost
	_ipdevs_data[newdev].port = remoteport

	_ipdevs_data[newdev].connect = auto_connect
	_ipdevs_data[newdev].reconnect = auto_connect

	return newdev;
}

DEFINE_FUNCTION INTEGER ip_create_udp(DEV ipDEV, CHAR name[_ip_manager_max_str], CHAR remotehost[_ip_manager_max_str], INTEGER remoteport) {
	STACK_VAR INTEGER newdev
	
	newdev = _ip_create_device(ipDEV)
	
	_ipdevs_data[newdev].name = name
	_ipdevs_data[newdev].ip_type = _ip_type_udp
	_ipdevs_data[newdev].remotehost = remotehost
	_ipdevs_data[newdev].port = remoteport

	_ipdevs_data[newdev].connect = 1
	_ipdevs_data[newdev].reconnect = 1

	return newdev;
}

DEFINE_FUNCTION INTEGER ip_create_ssh(DEV ipDEV, CHAR name[_ip_manager_max_str], CHAR remotehost[_ip_manager_max_str], INTEGER remoteport, CHAR user[_ip_manager_max_str], CHAR password[_ip_manager_max_str], INTEGER auto_connect) {
	STACK_VAR INTEGER newdev
	
	newdev = _ip_create_device(ipDEV)
	
	_ipdevs_data[newdev].name = name
	_ipdevs_data[newdev].ip_type = _ip_type_ssh
	_ipdevs_data[newdev].remotehost = remotehost
	_ipdevs_data[newdev].port = remoteport

	_ipdevs_data[newdev].ssh_user = user
	_ipdevs_data[newdev].ssh_password = password

	_ipdevs_data[newdev].connect = auto_connect
	_ipdevs_data[newdev].reconnect = auto_connect

	return newdev;
}

DEFINE_FUNCTION INTEGER ip_create_server_udp(DEV ipDEV, CHAR name[_ip_manager_max_str], INTEGER localport, INTEGER listen_start) {
	STACK_VAR INTEGER newdev
	
	newdev = _ip_create_device(ipDEV)
	
	_ipdevs_data[newdev].name = name
	_ipdevs_data[newdev].ip_type = _ip_type_server_udp
	_ipdevs_data[newdev].remotehost = '*'
	_ipdevs_data[newdev].port = localport

	_ipdevs_data[newdev].connect = listen_start
	_ipdevs_data[newdev].reconnect = listen_start

	return newdev;
}

DEFINE_FUNCTION INTEGER ip_create_server_tcp(DEV ipDEV, CHAR name[_ip_manager_max_str], INTEGER localport, INTEGER listen_start) {
	STACK_VAR INTEGER newdev
	
	newdev = _ip_create_device(ipDEV)
	
	_ipdevs_data[newdev].name = name
	_ipdevs_data[newdev].ip_type = _ip_type_server_tcp
	_ipdevs_data[newdev].remotehost = '*'
	_ipdevs_data[newdev].port = localport

	_ipdevs_data[newdev].connect = listen_start
	_ipdevs_data[newdev].reconnect = listen_start
	
	return newdev;
}


DEFINE_FUNCTION ip_set_rx_timeout(INTEGER iip, INTEGER seconds) {
	if (!_ipdevs_data[iip].reconnect) {
		log(_ip_manager_myid,logging_warning,"'Soft timeout should also have auto_connect enabled: ', _ipdevs_data[iip].name")
	}
	
	_ipdevs_data[iip].no_rx_timeout = seconds
}

// Manage connections
DEFINE_FUNCTION ip_close(DEV device) {
	STACK_VAR INTEGER iip
	
	iip = _ipdev_to_index(device)
	
	if (!iip)
		return;

	_ipdevs_data[iip].connect = 0
	_ipdevs_data[iip].reconnect = 0
	_ipdevs_data[iip].countdown = 0 // No more countdown
	_ip_check(iip)
}

DEFINE_FUNCTION ip_open(DEV device, INTEGER auto_reconnect) {
	STACK_VAR INTEGER iip
	
	iip = _ipdev_to_index(device)
	
	if (!iip)
		return;

	_ipdevs_data[iip].connect = 1
	_ipdevs_data[iip].reconnect = auto_reconnect
	_ipdevs_data[iip].countdown = 0 // Now!
	_ip_check(iip)
}

/*
#IF_NOT_DEFINED ip_manager_no_panel
// Init devices
DEFINE_FUNCTION ip_status_feedback(DEV device, INTEGER statusmode, INTEGER address) {
	STACK_VAR INTEGER iip
	iip = _ipdev_to_index(device)
	
	if (!iip)
		return;

	_ipdevs_data[iip].fbstatus_mode = statusmode
	_ipdevs_data[iip].fbstatus = 99
	_ipdevs_data[iip].fbbtn_addr = address
}

DEFINE_FUNCTION _ip_send_feedback(INTEGER iip, INTEGER ipanel) {
	/*
		INTEGER fbstatus_mode_off = 0
		INTEGER fbstatus_mode_channel = 1
		INTEGER fbstatus_mode_multistate = 2

		INTEGER fbstatus_unknown = 0
		INTEGER fbstatus_offline = 1
		INTEGER fbstatus_online = 2
		INTEGER fbstatus_deactivated = 3
		INTEGER fbstatus_listening = 4

		INTEGER fbstatus_mode
		INTEGER fbstatus
		INTEGER fbbtn_addr
	*/

	SWITCH (_ipdevs_data[iip].fbstatus_mode) {
		CASE fbstatus_mode_channel: {
			if (ipanel)
				[panels[ipanel],_ipdevs_data[iip].fbbtn_addr] = _ipdevs_data[iip].fbstatus==fbstatus_online
			else
				[panels,_ipdevs_data[iip].fbbtn_addr] = _ipdevs_data[iip].fbstatus==fbstatus_online
		}
		CASE fbstatus_mode_multistate: {
			panel_set_multistate(ipanel, _ipdevs_data[iip].fbbtn_addr, _ipdevs_data[iip].fbstatus)
		}
	}
}

DEFINE_FUNCTION _ip_send_feedback_panel(INTEGER ipanel) {
	STACK_VAR INTEGER iip
	if (ipanel) {
		for (iip=1;iip<=_ipdevs_last;iip++) {
			_ip_send_feedback(iip, ipanel)
		}
	}
}
#END_IF
*/

// Internal
DEFINE_FUNCTION INTEGER _ip_create_device(DEV ipDEV) {
/*
	TODO: Checking device
	
	STACK_VAR DEV newdev
	IF (DEVICE_ID(55:1:0) <> 0) {
		// device exists in the system
	}
*/
	_ipdevs_last++
	_ip_manager_port_to_devindex[ipDEV.port] = _ipdevs_last
#IF_DEFINED ip_manager_variable_devs
	// Auto enumerate dev local port
	ipdevs[_ipdevs_last] = 0:_ip_first_local_port+_ipdevs_last-1:0
	
	// Return dev to variable via argument
	ipDEV = ipdevs[_ipdevs_last]
#ELSE
	// Just copy to local array
	ipdevs[_ipdevs_last] = ipDEV
#END_IF
	SET_LENGTH_ARRAY(ipdevs,_ipdevs_last)
	REBUILD_EVENT()
	
	return _ipdevs_last;
}

DEFINE_FUNCTION _ip_check_all() {
	STACK_VAR INTEGER ip
	
	for (ip=1;ip<=_ipdevs_last;ip++) {
		_ip_check(ip)
	}
}

DEFINE_FUNCTION _ip_check(INTEGER ip) {
	if (_ipdevs_data[ip].state == ip_state_connected and _ipdevs_data[ip].last_rx_secs<65000)
		_ipdevs_data[ip].last_rx_secs++;
	
	if (_ipdevs_data[ip].countdown>0)
		_ipdevs_data[ip].countdown--;

	// Verbindung schließen?
	if ((_ipdevs_data[ip].state == ip_state_connected or _ipdevs_data[ip].state == ip_state_listening)
			and
			(!ip_manager_run
			 or !_ipdevs_data[ip].connect
			)
		 )
	{
		_ip_disconnect(ip)
	}
	
	if (_ipdevs_data[ip].state == ip_state_connected and (_ipdevs_data[ip].no_rx_timeout>0 and _ipdevs_data[ip].last_rx_secs>=_ipdevs_data[ip].no_rx_timeout)) {
		log(_ip_manager_myid,logging_info,"'Soft timeout: ', _ipdevs_data[ip].name")
		_ip_disconnect(ip)
	}

	if (
			(_ipdevs_data[ip].state != ip_state_connected)
			and
			(_ipdevs_data[ip].state != ip_state_connecting)
			and
			(_ipdevs_data[ip].state != ip_state_listening)
			and
			(_ipdevs_data[ip].countdown == 0)
			and
			ip_manager_run
			and
			_ipdevs_data[ip].connect
			and
			LENGTH_STRING(_ipdevs_data[ip].remotehost)
			and
			_ipdevs_data[ip].port > 0
			and
			_ipdevs_data[ip].ip_type > 0
		)
	{
		_ip_connect(ip)
	}
}

DEFINE_FUNCTION CHAR[_ip_manager_max_str] _ip_errorcode_description(INTEGER code) {
/*
					2 - General failure (out of memory)
					4 - Unknown host
					6 - Connection refused
					7 - Connection timed out
					8 - Unknown connection error
					9 - Already closed
					14 - Local port already used
					16 - Too many open sockets
					17: Local Port Not Open
*/

	SWITCH (code) {
		case 0:
			return 'No error';
		case 2:
			return 'General failure (out of memory)';
		case 4:
			return 'Unknown host';
		case 6:
			return 'Connection refused';
		case 7:
			return 'Connection timed out';
		case 8:
			return 'Unknown connection error';
		case 9:
			return 'Already closed';
		case 14:
			return 'Local port already used';
		case 16:
			return 'Too many open sockets';
		case 17:
			return 'Local Port Not Open';

		default:
			return 'unknown code';
	}
}


DEFINE_FUNCTION _ip_connect(INTEGER ip) {
	STACK_VAR SLONG ret
	
	log(_ip_manager_myid,logging_info,"'Connect(): ',_ipdevs_data[ip].name")
	
	if (ip_manager_disconnect_before_connect)
		_ip_disconnect(ip)
	
	log(_ip_manager_myid,logging_info,"'Connecting(): ',_ipdevs_data[ip].name, '[',_ipdevs_data[ip].remotehost,':',ITOA(_ipdevs_data[ip].port),']'")
	_ipdevs_data[ip].state = ip_state_connecting

/*
#IF_NOT_DEFINED ip_manager_no_panel
	_ipdevs_data[ip].fbstatus = fbstatus_connecting
#END_IF
*/

	SWITCH (_ipdevs_data[ip].ip_type) {
		CASE _ip_type_tcp: {
			IP_CLIENT_OPEN(ipdevs[ip].Port, _ipdevs_data[ip].remotehost, _ipdevs_data[ip].port, IP_TCP)
		}
		CASE _ip_type_tls: {
			TLS_CLIENT_OPEN(ipdevs[ip].Port, _ipdevs_data[ip].remotehost, _ipdevs_data[ip].port, TLS_IGNORE_CERTIFICATE_ERRORS)
		}
		CASE _ip_type_udp: {
			IP_CLIENT_OPEN(ipdevs[ip].Port, _ipdevs_data[ip].remotehost, _ipdevs_data[ip].port, IP_UDP_2WAY)
		}
		CASE _ip_type_server_udp: {
			IP_SERVER_OPEN(ipdevs[ip].Port, _ipdevs_data[ip].port, IP_UDP)
		}
		CASE _ip_type_server_tcp: {
			IP_SERVER_OPEN(ipdevs[ip].Port, _ipdevs_data[ip].port, IP_TCP)
			_ipdevs_data[ip].state = ip_state_listening
/*
#IF_NOT_DEFINED ip_manager_no_panel
			_ipdevs_data[ip].fbstatus = fbstatus_listening
#END_IF
*/
		}
		CASE _ip_type_ssh: {
			ret = SSH_CLIENT_OPEN(ipdevs[ip].Port,  _ipdevs_data[ip].remotehost, _ipdevs_data[ip].port, _ipdevs_data[ip].ssh_user, _ipdevs_data[ip].ssh_password, '', '')
			/*
					Returncodes:
					2 - General failure (out of memory)
					4 - Unknown host
					6 - Connection refused
					7 - Connection timed out
					8 - Unknown connection error
					9 - Already closed
					14 - Local port already used
					16 - Too many open sockets
			*/
			if (ret) {
				log(_ip_manager_myid,logging_error,"'Connect_Error [',_ipdevs_data[ip].name, '] code: ',ITOA(ret)")
			}
		}
	}

/*	
#IF_NOT_DEFINED ip_manager_no_panel
	_ip_send_feedback(ip,0)
#END_IF
*/
}

DEFINE_FUNCTION _ip_disconnect(INTEGER ip) {
	log(_ip_manager_myid,logging_info,"'Disconnect(): ',_ipdevs_data[ip].name")
	
	switch (_ipdevs_data[ip].ip_type) {
		case _ip_type_ssh:
			SSH_CLIENT_CLOSE(ipdevs[ip].PORT)
		case _ip_type_tcp:
			IP_CLIENT_CLOSE(ipdevs[ip].PORT)
		case _ip_type_tls:
			TLS_CLIENT_CLOSE(ipdevs[ip].PORT)
		case _ip_type_udp:
			IP_CLIENT_CLOSE(ipdevs[ip].PORT)
		case _ip_type_server_udp:
			IP_SERVER_CLOSE(ipdevs[ip].PORT)
		case _ip_type_server_tcp: {
			IP_SERVER_CLOSE(ipdevs[ip].PORT)
		}
	}

	if (_ipdevs_data[ip].ip_type == _ip_type_server_tcp) {
		_ipdevs_data[ip].state = ip_state_closed
/*
#IF_NOT_DEFINED ip_manager_no_panel
		_ipdevs_data[ip].fbstatus = fbstatus_listening
#END_IF
*/
	} else {
		_ipdevs_data[ip].state = ip_state_closing
/*
#IF_NOT_DEFINED ip_manager_no_panel
		_ipdevs_data[ip].fbstatus = fbstatus_offline
#END_IF
*/
	}

/*	
#IF_NOT_DEFINED ip_manager_no_panel
	_ip_send_feedback(ip,0)
#END_IF
*/
	_ip_schedule_reconnect(ip)
}

DEFINE_FUNCTION _ip_schedule_reconnect(INTEGER ip) {
	if (!_ipdevs_data[ip].reconnect)
		return;
	
	if (_ipdevs_data[ip].unsuccessful_connect_count >= ip_manager_retry_long_after)
		_ipdevs_data[ip].countdown = ip_manager_retry_long_interval
	else
		_ipdevs_data[ip].countdown = ip_manager_retry_interval
}

DEFINE_EVENT
DATA_EVENT[dvMaster] {
	ONLINE: {
		//_ip_manager_myid = logging_register_module('ip_manager', 'IP Manager', '_ip_manager.axi')
		ip_manager_run = 1 // Start connections
	}
}

DATA_EVENT[ipdevs] {
	ONLINE: {
		STACK_VAR INTEGER ip
		
		ip = GET_LAST(ipdevs)
		log(_ip_manager_myid,logging_info,"'ONLINE: ',_ipdevs_data[ip].name")
		_ipdevs_data[ip].state = ip_state_connected
		_ipdevs_data[ip].unsuccessful_connect_count = 0
		_ipdevs_data[ip].last_rx_secs = 0
		
/*
#IF_NOT_DEFINED ip_manager_no_panel
		_ipdevs_data[ip].fbstatus = fbstatus_online
		_ip_send_feedback(ip,0)
#END_IF
*/
	}

	OFFLINE: {
		STACK_VAR INTEGER ip
		
		ip = GET_LAST(ipdevs)
		log(_ip_manager_myid,logging_info,"'OFFLINE: ',_ipdevs_data[ip].name")
		
		//if (_ipdevs_data[ip].ip_type==_ip_type_server_tcp)
		//	_ipdevs_data[ip].state = ip_state_listening
		//else
			_ipdevs_data[ip].state = ip_state_closed
			_ipdevs_data[ip].last_rx_secs = 0

/*
#IF_NOT_DEFINED ip_manager_no_panel
		_ipdevs_data[ip].fbstatus = fbstatus_offline
		_ip_send_feedback(ip,0)
#END_IF
*/
	}

	STRING: {
		STACK_VAR INTEGER ip
		
		ip = GET_LAST(ipdevs)
		log(_ip_manager_myid,logging_rx,"_ipdevs_data[ip].name,': ',DATA.TEXT")

		_ipdevs_data[ip].state = ip_state_connected
		_ipdevs_data[ip].countdown=0
		_ipdevs_data[ip].last_rx_secs = 0
	}

	ONERROR: {
		STACK_VAR INTEGER ip
		
		ip = GET_LAST(ipdevs)

		if (DATA.NUMBER != 9 and DATA.NUMBER != 17) {
			// != already closed
			// != conn not open
			log(_ip_manager_myid,logging_error,"_ipdevs_data[ip].name,': Error ',ITOA(Data.Number)")
			_ipdevs_data[ip].state = ip_state_closed
			
			if (_ipdevs_data[ip].unsuccessful_connect_count<65535)
				_ipdevs_data[ip].unsuccessful_connect_count++
			
			_ip_schedule_reconnect(ip)
		}
	}
}

TIMELINE_EVENT[TL_1Second] {
	_ip_check_all()
}

/*
#IF_NOT_DEFINED ip_manager_no_panel
DATA_EVENT[vdvPanels] {
	COMMAND: {
		STACK_VAR CHAR cmdData[3]
		STACK_VAR INTEGER ipanel
		STACK_VAR CHAR igroup
		
		cmdData = DATA.TEXT
		
		switch (cmdData[1]) {
			case panel_event_update: {
				// args: panel, group
				ipanel = cmdData[2]
				_ip_send_feedback_panel(ipanel)
			}
		}
	}
}

TIMELINE_EVENT[TL_1Minute] {
	_ip_send_feedback_panel(0)
}


#END_IF
*/
