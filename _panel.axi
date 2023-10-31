PROGRAM_NAME='_panel'
#DEFINE ait_panel
/*
=== [Description] =============================================================
Panel management and helper functions


=== [Settings] =====================================================
panel_statistics_clear trigger to 1
PERSISTENT INTEGER panels_online_beep = 0
PERSISTENT INTEGER panels_inactivity_secs = 300


=== [Requirements] ============================================================
_common.axi
_logging.axi

DEFINE_CONSTANT
INTEGER panels_max = x // for memory optimization. Reserve some spare.
INTEGER rooms_max = x // maximal number of rooms or areas
#INCLUDE 'UnicodeLib.axi'


=== [Compile switches] ========================================================
panels_log_all // Log all button pushes
#DEFINE panel_roomname_addr iaddr

Address of multistate activity button on all panels (optional)
#DEFINE panel_activity_blink 3

=== [Example snippet] =========================================================
myPanel = panel_register(dvPanel,'Samsung Pad', 0, 0)


=== [Change log] ==============================================================
2019-08-21 panels_log_all feature
2019-08-27 Inactivity check
2019-10-24 room name handling
2019-11-21 Full keyboard and keypad handling
2019-12-20 Panel-Event: Room of panel changed

=== [TO-DOs] ==================================================================
Page tracking and logic

===============================================================================
*/

#INCLUDE 'UnicodeLib.axi'

/*
WC_DECODE
WC_ENCODE
cMyString = WC_TP_ENCODE(wcMyString)
SEND_COMMAND dvTP,"'^UNI-1,0,',cMyString "
*/

DEFINE_DEVICE
vdvPanels = 34205:1:0 // For event signaling

DEFINE_CONSTANT
//INTEGER panels_max = 8 -> Im Projekt deklarieren
INTEGER panel_vol_min = 0
INTEGER panel_vol_max = 1000 // Don't change! Standard!
INTEGER panel_page_history = 16
INTEGER panel_max_name_size = 32
INTEGER panel_eventrecord_count = 512

// COMMANDs on vdvPanels (byte 1)
INTEGER panel_event_update = 1 // byte2=panel, byte3=room
INTEGER panel_event_enter_inactivity = 2 // byte2=panel, byte3=room
INTEGER panel_event_exit_inactivity = 3 // byte2=panel, byte3=room
INTEGER panel_event_keyboard_result = 4 // byte2=panel, byte3=room, byte4=handle, byte5... text result
INTEGER panel_event_room_changed = 5 // byte2=panel, byte3=oldroom, byte4=newroom

DEFINE_TYPE
STRUCTURE _panel {
	CHAR name[panel_max_name_size]
	CHAR history[panel_page_history][panel_max_name_size+1] //Typ 1=Page, 2=Popup
	INTEGER history_channel_button[panel_page_history]
	INTEGER history_pos_scroll	// Wo man beim blättern ist
	INTEGER history_pos_last  // Letzte Seite
	INTEGER history_pos_first   // Erste Seite
	INTEGER isG5
	INTEGER rolecode
	INTEGER with_history_feedback
	INTEGER msg_countdown
	INTEGER inactivity_secs
	INTEGER is_online
	INTEGER inactive
	INTEGER is_dynamic
	INTEGER bios_panel
	INTEGER is_bios_for_panel
	DEV_INFO_STRUCT info
}

STRUCTURE _panel_persistent {
	CHAR current_page[panel_max_name_size]
	CHAR offline_event[panel_eventrecord_count][17]
	INTEGER offline_index
	INTEGER offline_event_count
	CHAR online_event[panel_eventrecord_count][17]
	INTEGER online_index
	INTEGER online_event_count
	CHAR room
	#WARN 'write events to disk'
}

DEFINE_VARIABLE

VOLATILE DEV panels[panels_max]
VOLATILE _panel _panels_data[panels_max]
PERSISTENT _panel_persistent _panels_data_persistent[panels_max]
PERSISTENT INTEGER panels_online_beep = 0
PERSISTENT INTEGER panels_inactivity_secs = 300 // 5 Min
VOLATILE INTEGER _panels_last
VOLATILE INTEGER _panel_disable_flips[panels_max]
VOLATILE INTEGER _panel_logid
VOLATILE INTEGER panel_active_pageid[panels_max]
VOLATILE CHAR panel_active_keyboard[panels_max]
VOLATILE INTEGER panel_statistics_clear = 0

#IF_DEFINED panel_activity_blink
VOLATILE INTEGER blink_activity
#END_IF

DEFINE_FUNCTION INTEGER panel_register(DEV dvpanel, CHAR name[panel_max_name_size], INTEGER isG5, INTEGER rolecode) {
	_panels_last++
	panels[_panels_last]=dvpanel
	_panels_data[_panels_last].name=name
	_panels_data[_panels_last].isG5=isG5
	_panels_data[_panels_last].rolecode=rolecode
	_panels_data[_panels_last].history_pos_scroll=0
	_panels_data[_panels_last].history_pos_last=0
	_panels_data[_panels_last].history_pos_first=0
	_panels_data[_panels_last].with_history_feedback=0
	_panels_data[_panels_last].inactivity_secs=0

	set_length_array(panels,_panels_last)
	set_length_array(_panels_data,_panels_last)

	REBUILD_EVENT()
	log(_panel_logid,logging_init,"'Panel "',_panels_data[_panels_last].name,'" registered'")

	return _panels_last
}

DEFINE_FUNCTION panel_historymode_enable(INTEGER ipanel) {
	_panels_data[ipanel].with_history_feedback=1
}

DEFINE_FUNCTION panel_update(INTEGER ipanel) {
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_init,"'Panel "',_panels_data[_panels_last].name,'" sending update request'")
#IF_DEFINED panel_roomname_addr
		panel_text(ipanel, panel_roomname_addr, roomnames[_panels_data_persistent[ipanel].room])
#END_IF
		SEND_COMMAND vdvPanels,"panel_event_update,ipanel,_panels_data_persistent[ipanel].room"
	}	else {
		for (i=1;i<=_panels_last;i++) {
			panel_update(i)
		}
	}
}

// room=0: all rooms -> all panels
DEFINE_FUNCTION panel_update_by_room(CHAR room) {
	STACK_VAR INTEGER i
	for (i=1;i<=_panels_last;i++) {
		if (_panels_data_persistent[i].room == room or (room==0)) {
			panel_update(i)
		}
	}
}


DEFINE_FUNCTION CHAR get_room_of_panel(INTEGER ipanel) {
	return _panels_data_persistent[ipanel].room
}

DEFINE_FUNCTION set_room_of_panel(INTEGER ipanel, CHAR iroom) {
	STACK_VAR INTEGER changed
	
	log(_panel_logid,logging_info,"'Assigning Panel id "',ITOA(ipanel),'" to room ',ITOA(iroom)")
	
	changed = _panels_data_persistent[ipanel].room != iroom
	_panels_data_persistent[ipanel].room = iroom
	
	if (changed) {
		SEND_COMMAND vdvPanels,"panel_event_room_changed,ipanel,_panels_data_persistent[ipanel].room,iroom"
		panel_update(ipanel)
	}
}

DEFINE_FUNCTION INTEGER panel_get_rolecode(INTEGER ipanel) {
	return _panels_data[ipanel].rolecode
}

DEFINE_FUNCTION _save_to_history(INTEGER ipanel, INTEGER typ, CHAR name[panel_max_name_size], INTEGER channel_button) {
	STACK_VAR INTEGER new_pos
	STACK_VAR CHAR page_id[panel_max_name_size+1]
// TODO: anderer Channcel-Code: zumindest feedback anpassen
	page_id="ITOA(typ),name"

	new_pos=_panels_data[ipanel].history_pos_scroll

	if (new_pos>0) // Mindestens ein Eintrag in der History
		if (_panels_data[ipanel].history[new_pos]=page_id) // Wechsel zur Seite auf der wir schon sind
			return;	// Speichern nur bei Wechsel auf neue Seite nötig.

	new_pos++
	if (new_pos>panel_page_history) new_pos=1

	if (new_pos=_panels_data[ipanel].history_pos_first) _panels_data[ipanel].history_pos_first=new_pos+1

	if (_panels_data[ipanel].history_pos_first=0 or _panels_data[ipanel].history_pos_first>panel_page_history)
		_panels_data[ipanel].history_pos_first=1

	_panels_data[ipanel].history[new_pos]=page_id

	_panels_data[ipanel].history_pos_last=new_pos
	_panels_data[ipanel].history_pos_scroll=new_pos
	_panels_data[ipanel].history_channel_button[new_pos]=channel_button
}

DEFINE_FUNCTION INTEGER panel_navigate_back(INTEGER ipanel) {
	log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Navigate back'")
	if (_panels_data[ipanel].history_pos_scroll != _panels_data[ipanel].history_pos_first) {
		if ( _panels_data[ipanel].history_pos_scroll=1) {
			_panels_data[ipanel].history_pos_scroll=panel_page_history
		} else {
			_panels_data[ipanel].history_pos_scroll--
		}
		_panel_navigate_toindex(ipanel, _panels_data[ipanel].history_pos_scroll)
		return 1
	} else {
		return 0
	}
}

DEFINE_FUNCTION INTEGER panel_navigate_forward(INTEGER ipanel) {
	log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Navigate forward'")
	if (_panels_data[ipanel].history_pos_scroll != _panels_data[ipanel].history_pos_last) {
		_panels_data[ipanel].history_pos_scroll++
		if (_panels_data[ipanel].history_pos_scroll>panel_page_history)
			_panels_data[ipanel].history_pos_scroll=1
		_panel_navigate_toindex(ipanel, _panels_data[ipanel].history_pos_scroll)
		return 1;
	} else {
		return 0;
	}
}

DEFINE_FUNCTION panel_clear_history(INTEGER ipanel) {
	log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' clear history'")
	_panels_data[ipanel].history_pos_scroll=0
	_panels_data[ipanel].history_pos_first=0
	_panels_data[ipanel].history_pos_last=0
}

DEFINE_FUNCTION _panel_navigate_toindex(INTEGER ipanel, INTEGER index) {
	STACK_VAR CHAR name[panel_max_name_size+1]
	STACK_VAR INTEGER typ

	name=_panels_data[ipanel].history[index]
	typ=GET_BUFFER_CHAR(name)

	log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Going to index ',ITOA(index)")

	if (typ='1') {
		panel_page_with_history(ipanel, name, 0, 0)
	}
	if (typ='2') {
		panel_popup_show_with_history(ipanel, name, 0, 0)
	}
}

DEFINE_FUNCTION _panel_clear_statistics(INTEGER ipanel) {
	STACK_VAR INTEGER xpanel
	STACK_VAR INTEGER irow
	
	if (ipanel) {
		for (irow=1;irow<=panel_eventrecord_count;irow++) {
			SET_LENGTH_STRING(_panels_data_persistent[ipanel].online_event[irow],0)
			_panels_data_persistent[ipanel].online_index = 0
			_panels_data_persistent[ipanel].online_event_count = 0
			
			SET_LENGTH_STRING(_panels_data_persistent[ipanel].offline_event[irow],0)
			_panels_data_persistent[ipanel].offline_index = 0
			_panels_data_persistent[ipanel].offline_event_count = 0

		}
	} else {
		for (xpanel=1;xpanel<=_panels_last;xpanel++) {
			_panel_clear_statistics(xpanel)
		}
	}
}

DEFINE_FUNCTION panel_history_clear(INTEGER ipanel) {
	log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' clear history'")

	if (_panels_data[ipanel].history_pos_scroll=0) {
		// Noch keine Seite gespeichert
		_panels_data[ipanel].history_pos_last=0
		_panels_data[ipanel].history_pos_first=0
	} else {
		// Nur aktuelle Seite übernehmen
		_panels_data[ipanel].history[1]=_panels_data[ipanel].history[_panels_data[ipanel].history_pos_scroll]
		_panels_data[ipanel].history_pos_scroll=1
		_panels_data[ipanel].history_pos_last=1
		_panels_data[ipanel].history_pos_first=1
	}
}

DEFINE_FUNCTION _panel_update_button_feedback() {
	STACK_VAR INTEGER i
	STACK_VAR INTEGER ihistory
	STACK_VAR INTEGER active_channel

	for (i=1;i<=_panels_last;i++) {
		if (_panels_data[i].with_history_feedback and _panels_data[i].history_pos_scroll) {
			active_channel=_panels_data[i].history_channel_button[_panels_data[i].history_pos_scroll]

			for (ihistory=1;ihistory<=panel_page_history;ihistory++) {
				if (_panels_data[i].history_channel_button[ihistory]) {
					[panels[i],_panels_data[i].history_channel_button[ihistory]] =
						_panels_data[i].history_channel_button[ihistory]=active_channel
				}
			}
		}
	}
}

DEFINE_FUNCTION panel_page(INTEGER ipanel, CHAR name[panel_max_name_size]) { // ^PGE
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Page ',name")
		
		_panels_data_persistent[ipanel].current_page = name
		if (!_panel_disable_flips[ipanel])
			SEND_COMMAND panels[ipanel],"'PAGE-',name"
	} else {
		for (i=1;i<=_panels_last;i++)
			panel_page(i,name)
	}
}

DEFINE_FUNCTION panel_page_by_room(CHAR iroom, CHAR name[panel_max_name_size]) { // ^PGE
	STACK_VAR INTEGER i

	log(_panel_logid,logging_info,"'Panel of room ',ITOA(iroom),' Page ',name")

	for (i=1;i<=_panels_last;i++) {
		if (_panels_data_persistent[i].room == iroom or (iroom==0)) {
			_panels_data_persistent[i].current_page = name
			if (!_panel_disable_flips[i])
				SEND_COMMAND panels[i],"'PAGE-',name"
		}
	}
}

DEFINE_FUNCTION panel_page_with_history(INTEGER ipanel, CHAR name[panel_max_name_size], INTEGER save_to_history, INTEGER caller_channel) {
	log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Page ',name,' save_to_history:',ITOA(save_to_history)")
	if (save_to_history) _save_to_history(ipanel, 1, name, caller_channel)
	if (!_panel_disable_flips[ipanel])
		SEND_COMMAND panels[ipanel],"'PAGE-',name"
}

DEFINE_FUNCTION panel_popup_show_by_room(CHAR room, CHAR name[panel_max_name_size]) {
	STACK_VAR INTEGER i
	for (i=1;i<=_panels_last;i++) {
		if (_panels_data_persistent[i].room == room or (room==0)) {
			panel_popup_show(i, name)
		}
	}
}

DEFINE_FUNCTION panel_popup_hide_by_room(CHAR room, CHAR name[panel_max_name_size]) {
	STACK_VAR INTEGER i
	for (i=1;i<=_panels_last;i++) {
		if (_panels_data_persistent[i].room == room or (room==0)) {
			panel_popup_hide(i, name)
		}
	}
}

DEFINE_FUNCTION panel_popup_show(INTEGER ipanel, CHAR name[panel_max_name_size]) {
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Popup show: ',name")
		if (!_panel_disable_flips[ipanel])
			SEND_COMMAND panels[ipanel],"'PPON-',name"
	} else {
		for (i=1;i<=_panels_last;i++)
			panel_popup_show(i,name)
	}
}

DEFINE_FUNCTION panel_popup_toggle(INTEGER ipanel, CHAR name[panel_max_name_size]) {
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Popup toggle: ',name")
		if (!_panel_disable_flips[ipanel])
			SEND_COMMAND panels[ipanel],"'PPOG-',name"
	}
}

DEFINE_FUNCTION panel_popup_show_with_history(INTEGER ipanel, CHAR name[panel_max_name_size], INTEGER save_to_history, INTEGER caller_channel) {
	log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Popup show: ',name,' save_to_history:',ITOA(save_to_history)")
	if (!_panel_disable_flips[ipanel])
		SEND_COMMAND panels[ipanel],"'PPON-',name"
	if (save_to_history)
		_save_to_history(ipanel, 2, name, caller_channel)
}


DEFINE_FUNCTION panel_popup_hide(INTEGER ipanel, CHAR name[panel_max_name_size]) {
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' Popup hide: ',name")
		if (!_panel_disable_flips[ipanel])
			SEND_COMMAND panels[ipanel],"'PPOF-',name"
	} else {
		for (i=1;i<=_panels_last;i++)
			panel_popup_hide(i,name)
	}
}

DEFINE_FUNCTION panel_popup_hideall(INTEGER ipanel) {
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,': hide all popups'")
		if (!_panel_disable_flips[ipanel])
			SEND_COMMAND panels[ipanel],"'@PPX'"
	} else {
		for (i=1;i<=_panels_last;i++)
			panel_popup_hideall(i)
	}
}

DEFINE_FUNCTION panel_popupgroup_hide(INTEGER ipanel, CHAR name[panel_max_name_size]) {
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,': popup group hide: ',name")
		if (!_panel_disable_flips[ipanel])
			SEND_COMMAND panels[ipanel],"'@CPG-',name"
	} else {
		for (i=1;i<=_panels_last;i++)
			panel_popupgroup_hide(i,name)
	}
}


// Popup "wait_msg", Text-Address 3000
DEFINE_FUNCTION panel_wait_msg(INTEGER ipanel, CHAR msg[], CHAR title[], INTEGER timeout_sec) {
	STACK_VAR INTEGER i
	if (ipanel) {
		log(_panel_logid,logging_info,"'Panel ',_panels_data[ipanel].name,' wait-msg'")
		panel_text(ipanel,3000,msg)
		panel_text(ipanel,3001,title)
		panel_popup_show(ipanel,'wait_msg')
		_panels_data[ipanel].msg_countdown=timeout_sec
	} else {
		for (i=1;i<=_panels_last;i++) {
			panel_wait_msg(i, msg, title,timeout_sec)
		}
	}
}

DEFINE_FUNCTION panel_set_wake(INTEGER ipanel, INTEGER wake_status) {
	if (wake_status)
		SEND_COMMAND panels[ipanel], "'WAKE'"
	else
		SEND_COMMAND panels[ipanel], "'SLEEP'"
}


DEFINE_FUNCTION panel_playSound(INTEGER ipanel, CHAR soundFile[]) {
	if (_panels_data[ipanel].isG5)
		SEND_COMMAND panels[ipanel], "'^SOU-',soundFile"
	else
		SEND_COMMAND panels[ipanel], "'@SOU-',soundFile"
}

DEFINE_FUNCTION panel_playStop(INTEGER ipanel) {
	if (_panels_data[ipanel].isG5)
		SEND_COMMAND panels[ipanel], "'^SOU-empty.wav'"
	else
		SEND_COMMAND panels[ipanel], "'@SOU-empty.wav'"
}

DEFINE_FUNCTION panel_set_multistate(INTEGER ipanel, INTEGER address, INTEGER state) {
	if (ipanel)
		SEND_COMMAND panels[ipanel], "'^ANI-',ITOA(address),',',ITOA(state),',',ITOA(state),',0'"
	else
		SEND_COMMAND panels, "'^ANI-',ITOA(address),',',ITOA(state),',',ITOA(state),',0'"
}

DEFINE_FUNCTION panel_text_from_utf8(INTEGER ipanel, INTEGER address, CHAR txt[]) {
/*
^UNI
Set Unicode text. For the ^UNI command (%UN and ^BMF command), the Unicode text is sent as
ASCII-HEX nibbles.
Syntax:
"'^UNI-<vt addr range>,<button states range>,<unicode text>'"
Variable:
variable text address range = 1 - 4000.
button states range = 1 - 256 for multi-state buttons (0 = All states, for General buttons
1 = Off state and 2 = On state).
unicode text = Unicode HEX value.   
Example:
SEND_COMMAND Panel,"'^UNI-500,1,0041'"
Sets the button’s unicode character to ’A’.
Note: To send the variable text ’A’ in unicode to all states of the variable text
button 1, (for which the character code is 0041 Hex), send the following command:
 SEND_COMMAND TP,"'^UNI-1,0,0041'"
Note: Unicode is always represented in a HEX value. TPD4 generates (through the Text Enter Box dialog) unicode HEX values. Refer to the TPDesign4 Instruction Manual for more information.
*/
	STACK_VAR WIDECHAR wide[2048]
	STACK_VAR CHAR txttp[2048]
	
	wide = WC_DECODE(txt, WC_FORMAT_UTF8, 1)

	txttp = WC_TP_ENCODE(wide)

	if (ipanel) {
		SEND_COMMAND panels[ipanel], "'^UNI-',ITOA(address),',0,',txttp"
	} else {
		SEND_COMMAND panels, "'^UNI-',ITOA(address),',0,',txttp"
	}


}


// Text an Panel senden
// ipanel=0 -> Alle Panels
DEFINE_FUNCTION panel_text(INTEGER ipanel, INTEGER address, CHAR txt[]) {
	if (ipanel) {
		SEND_COMMAND panels[ipanel], "'^TXT-',ITOA(address),',0,',txt"
	} else {
		SEND_COMMAND panels, "'^TXT-',ITOA(address),',0,',txt"
	}
}

DEFINE_FUNCTION panel_text_ex(INTEGER ipanel, INTEGER address, CHAR txt[], INTEGER state) {
	STACK_VAR INTEGER i

	if (ipanel=0) {
		for (i=1;i<=_panels_last;i++) {
			panel_text_ex(i, address, txt, state)
		}
	} else {
			SEND_COMMAND panels[ipanel], "'^TXT-',ITOA(address),',',ITOA(state),',',txt"
	}
}

// Value 0-255 means "visibility"
DEFINE_FUNCTION panel_button_opacity(INTEGER ipanel, INTEGER ibtn, CHAR value) {
	if (ipanel)
		SEND_COMMAND panels[ipanel],"'^BOP-',ITOA(ibtn),',0,',ITOA(value)"
	else
		SEND_COMMAND panels,"'^BOP-',ITOA(ibtn),',0,',ITOA(value)"
}

// Button aktiv 0/1 (Push, Hit-Sounds, ...)
DEFINE_FUNCTION panel_button_enable(INTEGER ipanel, INTEGER ibtn, INTEGER value) {
	if (ipanel)
		SEND_COMMAND panels[ipanel],"'^ENA-',ITOA(ibtn),',',ITOA(value)"
	else
		SEND_COMMAND panels,"'^ENA-',ITOA(ibtn),',',ITOA(value)"
}

// Button sichtbar
DEFINE_FUNCTION panel_button_visible(INTEGER ipanel, INTEGER ibtn, INTEGER value) {
	if (ipanel)
		SEND_COMMAND panels[ipanel],"'^SHO-',ITOA(ibtn),',',ITOA(value)"
	else
		SEND_COMMAND panels,"'^SHO-',ITOA(ibtn),',',ITOA(value)"
}

DEFINE_FUNCTION panel_beep(INTEGER ipanel) {
	if (ipanel)
		SEND_COMMAND panels[ipanel],'ABEEP'
	else
		SEND_COMMAND panels,'ABEEP'
}

DEFINE_FUNCTION panel_dbeep(INTEGER ipanel) {
	if (ipanel)
		SEND_COMMAND panels[ipanel],'ADBEEP'
	else
		SEND_COMMAND panels,'ADBEEP'
}

DEFINE_FUNCTION panel_setup(INTEGER ipanel) {
	SEND_COMMAND panels[ipanel],'SETUP'
}

DEFINE_FUNCTION panel_open_browser_kiosk(INTEGER ipanel, CHAR url[]) {
	STACK_VAR CHAR cmd[256]
	
	cmd="'^APP-0,0,1280,800,8,Browser,FULLSCREEN,bool,true,URI,String,',url"
	
	if (ipanel)
		SEND_COMMAND panels[ipanel],cmd
	else
		SEND_COMMAND panels,cmd
}

DEFINE_FUNCTION CHAR panel_open_keyboard(INTEGER ipanel, INTEGER withalpha, CHAR inittext[128], CHAR prompttext[128]) {
	STACK_VAR CHAR kmode
	//@AKB-<initial text>;<prompt text>
	//@AKP-<initial text>;<prompt text>
	//AKEYP-<initial text>
	//AKEYB-<initial text>
	
	if (withalpha)
		kmode='B' // Keyboard
	else
		kmode='P' // Keypad

	panel_active_keyboard[ipanel]=RANDOM_NUMBER(255)+1
		
	if (_panels_data[ipanel].isG5) {
		if (LENGTH_STRING(prompttext)) {
			SEND_COMMAND panels[ipanel],"'@AK',kmode,'-',inittext,';',prompttext"
		} else {
			SEND_COMMAND panels[ipanel],"'@AK',kmode,'-',inittext"
		}
	} else {
		// G4
		SEND_COMMAND panels[ipanel],"'AKEY',kmode,'-',inittext"
	}
	
	return panel_active_keyboard[ipanel];
}

DEFINE_FUNCTION _panel_check_countdown() {
	STACK_VAR INTEGER ipanel
	for (ipanel=1;ipanel<=_panels_last;ipanel++) {
		if (_panels_data[ipanel].inactivity_secs<65536 and _panels_data[ipanel].is_online) {
			_panels_data[ipanel].inactivity_secs++
			if (_panels_data[ipanel].inactivity_secs == panels_inactivity_secs) {
				SEND_COMMAND vdvPanels,"panel_event_enter_inactivity,ipanel,_panels_data_persistent[ipanel].room"
				_panels_data[ipanel].inactive=1
			}
		}
		
		if (_panels_data[ipanel].msg_countdown>0) {
			_panels_data[ipanel].msg_countdown--
			
			if (_panels_data[ipanel].msg_countdown=0) {
				panel_popup_hide(ipanel,'wait_msg')
			}
		}
	}
}

DEFINE_FUNCTION INTEGER panel_inactivity(INTEGER ipanel) {
	return _panels_data[ipanel].inactive;
}

/*
"'TPAGEON'"  ^TPN (G5)
      Turn On page tracking. This command turns On page tracking, whereby when the
       page or popups change, a string is sent to the Master. This string may be
       captured with a CREATE_BUFFER command for one panel and sent directly to
       another panel.   
 
      Syntax:
            SEND_COMMAND <DEV>,"'TPAGEON'"

      Example:
            SEND_COMMAND Panel,"'TPAGEON'"
            Turns On page tracking.
 
   "'TPAGEOFF'" ^TPF (G5)
      Turn Off page tracking.
      Syntax:
            SEND_COMMAND <DEV>,"'TPAGEOFF'"

      Example:
            SEND_COMMAND Panel,"'TPAGEOFF'"
            Turns Off page tracking.


*/

//TPI-PRO
//   ORES-1920x1080@60
//   ^BOS-Addr,States,Input-Card,Passthrough

// USB Pass through
// ^PPS-{0/1}

DEFINE_EVENT

DATA_EVENT[panels] {
	ONLINE: {
		STACK_VAR INTEGER ipanel
		ipanel = GET_LAST(panels)		
		
		DEVICE_INFO(DATA.DEVICE, _panels_data[ipanel].info)
		
		log(_panel_logid,logging_info,"'ONLINE: Panel ',ITOA(ipanel),' "',_panels_data[ipanel].name,'" <',_panels_data[ipanel].info.device_id_string,'>'")
		
		_panels_data[ipanel].is_online = 1
		
		_panels_data_persistent[ipanel].online_index = (_panels_data_persistent[ipanel].online_index % panel_eventrecord_count) + 1
		_panels_data_persistent[ipanel].online_event[_panels_data_persistent[ipanel].online_index] = TIMESTAMP_German()
		_panels_data_persistent[ipanel].online_event_count++
		
		_panels_data[ipanel].inactivity_secs = 0
		
		panel_update(ipanel)

#IF_DEFINED panel_activity_blink
	// Sync
	OFF[panels[ipanel],panel_activity_blink]
	ON[panels[ipanel],panel_activity_blink]
#END_IF
		
		if (panels_online_beep)
			panel_beep(ipanel)
	}

	OFFLINE: {
		STACK_VAR INTEGER ipanel
		ipanel = GET_LAST(panels)
		_panels_data[ipanel].is_online = 0

		_panels_data_persistent[ipanel].offline_index = (_panels_data_persistent[ipanel].offline_index % panel_eventrecord_count) + 1
		_panels_data_persistent[ipanel].offline_event[_panels_data_persistent[ipanel].offline_index] = TIMESTAMP_German()
		_panels_data_persistent[ipanel].offline_event_count++

		log(_panel_logid,logging_info,"'OFFLINE: Panel ',ITOA(ipanel),' "',_panels_data[ipanel].name,'"'")
	}
	
	STRING: {
		STACK_VAR INTEGER ipanel
		STACK_VAR CHAR strdata[256]
		
		ipanel = GET_LAST(panels)
		strdata = DATA.TEXT
		
		if (FIND_STRING(strdata,'KEYB-',1)) {
			REMOVE_STRING(strdata,'KEYB-',1)
			
			if (strdata<>'ABORT') {
				// byte2=panel, byte3=room, byte4=handle, byte5... text result
				SEND_COMMAND vdvPanels,"panel_event_keyboard_result,ipanel,_panels_data_persistent[ipanel].room,panel_active_keyboard[ipanel],strdata"
			}
			panel_active_keyboard[ipanel]=0
		}
		
		if (FIND_STRING(strdata,'KEYP-',1)) {
			REMOVE_STRING(strdata,'KEYP-',1)
			
			if (strdata<>'ABORT') {
				// byte2=panel, byte3=room, byte4=handle, byte5... text result
				SEND_COMMAND vdvPanels,"panel_event_keyboard_result,ipanel,_panels_data_persistent[ipanel].room,panel_active_keyboard[ipanel],strdata"
			}
			panel_active_keyboard[ipanel]=0
		}
	}
}

BUTTON_EVENT[panels,0] {
	PUSH: {
		STACK_VAR INTEGER ipanel
		ipanel = GET_LAST(panels)
		
#IF_DEFINED panels_log_all
		log(_panel_logid,logging_usage_statistics,"'PUSH: P',ITOA(ipanel),': "',ITOA(BUTTON.INPUT.CHANNEL),'"'")
#END_IF
		
		if (_panels_data[ipanel].inactivity_secs > panels_inactivity_secs) {
			SEND_COMMAND vdvPanels,"panel_event_exit_inactivity,ipanel,_panels_data_persistent[ipanel].room"
			_panels_data[ipanel].inactive=0
		}
		_panels_data[ipanel].inactivity_secs = 0
	}
#IF_DEFINED panels_log_all
	HOLD[10,REPEAT]: {
		STACK_VAR INTEGER ipanel
		ipanel = GET_LAST(panels)
		log(_panel_logid,logging_usage_statistics,"'REPEAT[10]: P',ITOA(ipanel),': "',ITOA(BUTTON.INPUT.CHANNEL),'"'")
	}
	RELEASE: {
		STACK_VAR INTEGER ipanel
		ipanel = GET_LAST(panels)
		log(_panel_logid,logging_usage_statistics,"'RELEASE: P',ITOA(ipanel),': "',ITOA(BUTTON.INPUT.CHANNEL),'"'")
	}
#END_IF
}


DATA_EVENT[dvMaster] {
	ONLINE: {
		_panel_logid=logging_register_module('Panel','Panel manager','_panel.axi')
	}
}

TIMELINE_EVENT[TL_5Second] {
	if (!silent)
		_panel_update_button_feedback()
}

TIMELINE_EVENT[TL_1Second] {
	_panel_check_countdown()
	
	if (panel_statistics_clear) {
		panel_statistics_clear = 0
		_panel_clear_statistics(0)
	}
}

#IF_DEFINED panel_activity_blink
TIMELINE_EVENT[TL_Blink] {
	if (system_online) {
		blink_activity = (blink_activity % 3) + 1
		panel_set_multistate(0, panel_activity_blink, blink_activity + 1)
	}
}
#END_IF


// TODO: Navigation-Map: Button-Press -> Page/Popup
