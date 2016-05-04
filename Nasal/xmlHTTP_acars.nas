################################################################################
# Merlion Virtual Airlines ACARS and AutoPirep                                 #
# copyright Merlion Virtual Airlines - http://flymerlion.org                   #
#                                                                              #
# File Location: $FG_DATA/Nasal/xmlHTTP_acars.nas                              #
# Please DO NOT modify and redistribute this module, it is meant to be used by #
# registered merlion pilots only.                                              #
################################################################################

# Add the merlion menu to the menu bar

io.read_properties(getprop("/sim/fg-root")~"/gui/merlion.xml", "/sim/menubar/default");
var args = props.Node.new({
	"subsystem" : "gui",
});
fgcommand("reinit", args);

var targetnode = "/acars/server-response/";

var apiCheck = func() {
	var args = props.Node.new({
		"url" : "http://flymerlion.org/fgapi",
		"targetnode" : targetnode
	});
	fgcommand("xmlhttprequest", args);
};

var closestAirport = func() {
	return getprop("/sim/airport/closest-airport-id");
};

var aircraftType = func() {
	var aero = getprop("/sim/aero");
	if(aero == "787") {
		aero =  "787-8";
	}
	if(aero == "Embraer170") {
	    aero = "ERJ-170";
	}
	if(aero == "Embraer190") {
	    aero = "ERJ-190";
	}
	if(aero == "B757-200PF") {
		aero =  "757-200PF";
	}
	return aero;
};

var checkAircraft = func() {
	var aero = aircraftType();
	if(aero == "787") {
		aero =  "787-8";
	}
	if(aero == "Embraer170") {
	    aero = "ERJ-170";
	}
	if(aero == "Embraer190") {
	    aero = "ERJ-190";
	}
	if(aero == "B757-200PF") {
		aero =  "757-200PF";
	}
	var args = props.Node.new({
		"url" : "http://flymerlion.org/fgapi/checkAircraft/" ~ aero,
		"targetnode" : targetnode
	});
	fgcommand("xmlhttprequest", args);
};

var auth = func() {
	var pilotID = getprop("/acars/user/pilotid");
	var password = getprop("/acars/user/password");
	var args = props.Node.new({
		"url" : "http://flymerlion.org/fgapi/auth/" ~ pilotID ~ "/" ~ password,
		"targetnode" : targetnode
	});
	fgcommand("xmlhttprequest", args);
}

var findReplace = func(str) {
	for(var n=0; n<size(str); n+=1) {
		if((chr(str[n]) == ",") or (chr(str[n]) == " ")) {
			str = substr(str, 0, n) ~ "%20" ~ substr(str, n+1);
		} 
	}
	return str;
}

var getFlights = func() {
	var depicao = closestAirport();
	var actype = aircraftType();
	
	var args = props.Node.new({
		"url" : "http://flymerlion.org/fgapi/getFlights/" ~ depicao ~ "/" ~ actype,
		"targetnode" : targetnode
	});
	fgcommand("xmlhttprequest", args);
}

var getUser = func() {
	var auth = 0;	
	if(getprop("/acars/server-response/auth/code") == 1) {
		auth = getprop("/acars/server-response/auth/pilot/id");
	}
	
	if (auth == 0) {
		return nil;
	} else {
		var user = "/acars/server-response/auth/pilot/";
		var m = {
			id: getprop(user~"id"),
			name: getprop(user~"name"),
			rank: getprop(user~"rank"),
			flights: getprop(user~"flights"),
			hours: getprop(user~"hours"),
			code: getprop(user~"code"),
			hub: getprop(user~"hub")
		};
		return m;
	}
}

var acars_loop = {
   init : func {
		me.UPDATE_INTERVAL = 30;
		setprop("/acars/active", 0);
		setprop("/acars/fpln-filed", 0);
		setprop("/acars/flight/start-fuel", 0);
		setprop("/acars/flight/ready-pirep", 0);
		setprop("/acars/flight/trans-count", 0);
		setprop("/acars/transmit-msg", "ROUTINE CHECK ... ALL CLEAR");
		me.loopid = 0;
		me.reset();
},
	update : func {
	
	if(getprop("/acars/active") == 1) {
	
		var startFuel = getprop("/acars/flight/start-fuel");
		var currentFuel = getprop("/consumables/fuel/total-fuel-kg");
		if(currentFuel > startFuel) {
			# This is in case the pilot started the flight before filling up the aircraft
			setprop("/acars/flight/start-fuel", currentFuel);
		}
	
		# Collect data and send using xmlHTTPrequest
		var bookingid = getprop("/acars/server-response/booking/id");
		
		var authkey = getprop("/acars/server-response/auth/key");
		
		var latitude = getprop("/position/latitude-deg"); # Always same as gps data
		var longitude = getprop("/position/longitude-deg"); # Always same as gps data
		var altitude = getprop("/instrumentation/altimeter/indicated-altitude-ft");
		if(altitude == nil) {
			altitude = getprop("/position/altitude-ft");
		} elsif(altitude < 18000) {
			altitude = getprop("/position/altitude-ft");
		}
		
		var heading = getprop("/instrumentation/magnetic-compass/indicated-heading-deg");
		if(heading == nil) {
			heading = getprop("/orientation/heading-magnetic-deg");
		}
		
		var gspeed = getprop("/velocities/groundspeed-kt");
		
		var msg = getprop("/acars/transmit-msg");
		
		var utc = getprop("/sim/time/utc/day-seconds") - getprop("/sim/time/warp");
					
		if(utc < 0) {
			utc += 86400;
		} elsif(utc > 86400) {
			utc -= 86400;
		}
		
		var utcHrs = utc/3600;
		var utcMin = (utcHrs - int(utcHrs)) * 60;
		
		var utchrs = int(utcHrs);
		if(utchrs < 1) {
			utchrs = '00';
		} elsif(utchrs < 10) {
			utchrs = '0'~utchrs;
		}
		
		var utcmin = int(utcMin);
		if(utcmin < 1) {
			utcmin = '00';
		} elsif(utcmin < 10) {
			utcmin = '0'~utcmin;
		}
		
		var utcString = utchrs~utcmin;
		
		setprop("/acars/last-tx-utc", utcString);
				
		# Format: http://flymerlion.org/fgapi/acarsTransmit/<bookingid>/<authkey>/<latitude>/<longitude>/<altitude>/<heading>/<gspeed>/<msg>/<utc>
		
		var targetnode = "/acars/server-response";
		
		var args = props.Node.new({
			"url" : "http://flymerlion.org/fgapi/acarsTransmit/"~bookingid~"/"~authkey~"/"~latitude~"/"~longitude~"/"~int(altitude)~"/"~heading~"/"~gspeed~"/"~findReplace(msg)~"/"~findReplace(utcString),
			"targetnode" : targetnode
		});
		fgcommand("xmlhttprequest", args);
		
		setprop("/acars/flight/trans-count", getprop("/acars/flight/trans-count") + 1);
	
	}
	
},

	reset : func {
		me.loopid += 1;
		me._loop_(me.loopid);
},
	_loop_ : func(id) {
		id == me.loopid or return;
		me.update();
		settimer(func { me._loop_(id); }, me.UPDATE_INTERVAL);
}

};

acars_loop.init();
