s.boot;
s.reboot;
s.quit;

//INICIO
//--------------------
(
//SynthDef
var types = ['saw', 'perlin', 'sine', 'line' ];

///Grain player
SynthDef(\simpleGrain, {|bufnum, out = 0, pan = 0, pos = 0, size = 0.2, tr = 1, trD = 0, gn = 1|
	var env, sig, envctl, curTr;
	envctl = Env(levels: [0,1,0.25,0], times: [0.25, 0.25, 0.5], curve: [\welch, \welch, \sqr]);
	curTr = tr + (trD * BrownNoise.kr());
	sig = PlayBuf.ar(1, bufnum, BufRateScale.kr(bufnum) * curTr, startPos: pos);
	sig = sig * EnvGen.ar(envctl, levelScale: gn, timeScale: size, doneAction: 2);
	Out.ar(out, Pan2.ar(sig, pan));
}).add;

///Lfo
types.do({arg i;
	SynthDef(i, {|in=0, gesture = 0, start = 0, end = 1, per = 1|
	var trig, out, freq, update;
	update = 20;
	freq = 1 / per;
	trig = Impulse.kr(update);

	out = switch(i,
		'saw', {out = LFSaw.kr(freq).range(start, end)},
		'perlin', {out = Perlin3.kr(PulseCount.kr(trig) * (freq/update)).range(start, end)},
		'sine', {out = SinOsc.kr(freq).range(start, end)},
		'line', {out = Line.kr(start, end, per)}
	);

	if(out == nil, {out = Line.kr(0, 1, per)});
	SendReply.kr(trig, '/sReply',[gesture, out]);
}).add;
});

//Envelope
SynthDef(\envGen, { |in = 0, out = 0, time = 1, done = 2|
	var sig, env, envCtl;
	sig = In.ar(in, 2);
	env = Env.newClear(4);
	envCtl = \env.ir(env.asArray);
	ReplaceOut.ar(out, sig * EnvGen.kr(envCtl, timeScale: time, doneAction: done));
}).add;

//Variables
~fuentes = Dictionary.new;
~grGroup = Group.new;
~osc = Array.new;
~active = false;
~global = false;
~print = false;

~parameters = Dictionary.new;
~srcPar = Dictionary.new;

~parameters["size"] = 0.2;
~parameters["transpose"] = 1;
~parameters["gain"] = 0.3;
~parameters["dens"] = 4;
~parameters["rTranspose"] = 0;


~glGain = 1;
~arMode = 0;
)
//OSC
//--------------------
(
var newFile, newGrain, clear, parReceive;
var lfoSend;

NetAddr.localAddr.postln;
~address = NetAddr.new("127.0.0.1", 8333);

if(~osc != nil, {~osc.do({arg i; i.free})});
~osc = Array.new(4);

//send
newFile = OSCFunc({ arg msg, time, addr, recvPort;
	msg[1].asString.postln;
	~fuentes.put(msg[1].asString, Buffer.read(s, msg[1]));
	~srcPar.put(msg[1].asString, ~parameters);
}, '/newFile', n);

newGrain = OSCFunc({ arg msg, time, addr, recvPort;
	~activas = Array2D.new(msg[1], 2);
	msg[1].do({arg i;
		var index = i * 3;
		~activas.put(i,0,msg[2 + index]);
		~activas.put(i,1,msg[3 + index]);
	});
}, '/newGrain', n);

clear = OSCFunc({ arg msg, time, addr, recvPort;
	~fuentes.clear();
	~srcPar.clear;
	~active = false;
	if(msg[1], {"init".postln}, {"clear".postln});
}, '/clear', n);


parReceive = OSCFunc({ arg msg, time, addr, recvPort;
	~setPar.value(msg[1], msg[2], msg[3], msg[4], msg[5], msg[6]);
}, '/parameters', n);

//receive
lfoSend = OSCdef(\listener, {|msg|
	var data = msg[3..];
	~address.sendMsg("/gesture", data[0].asInt, data[1]);
}, '/sReply');



~osc.add(newFile);
~osc.add(newGrain);
~osc.add(clear);
~osc.add(parReceive);
~osc.add(lfoSend);
)

//ARDUINO
//--------------------
SerialPort.devices;

(

)

//CONTROL
//--------------------
(
~gestTrig = {
	//para golpe
};

~setPar = {|src = "", tr = 1, rTr = 0, size=0.3, dens=4, gain = 1|
	var parameters = Dictionary.new();
	parameters["transpose"] = tr;
	parameters["rTranspose"] = rTr;
	parameters["size"] = size;
	parameters["dens"] = dens;
	parameters["gain"] = gain;
	~srcPar.put(src, parameters);
};

~sendPar = {|gesture = 1|
	~srcPar.keysValuesDo {|keys, values|
		var key = keys;
		~address.sendMsg(
			"/setSimpleParameters",
			gesture,
			key,
			values["transpose"].asFloat,
			values["rTranspose"].asFloat,
			values["size"].asFloat,
			values["dens"].asFloat,
			values["gain"].asFloat,
		);
	};
};

~lfoFunc = {|flatness = -1.0, rms = -1.0, centroid = -1.0, rolloff = -1.0, bandwidth = -1.0|
	~address.sendMsg("/lfo", flatness, rms, centroid, rolloff, bandwidth);
};

//GENERADOR
//--------------------
~routine = Routine.new({
	inf.do({
		if(~activas.class == Array2D, {
			var selected, fuente, size, tr, trD, gn, hop, grain;
			selected = ~activas.rows.rand;
			fuente = ~activas.at(selected, 0).asString;

			size = ~parameters.at("size");
			tr = ~parameters.at("transpose");
			trD = ~parameters.at("rTranspose");
			gn = ~parameters.at("gain");
			hop = size / ~parameters.at("dens");

			if(~global.not, {
				//var sFuente = fuente.asSymbol;
				var sFuente = fuente;
				if(~print == true, {sFuente.postln});
				if(~srcPar.trueAt(sFuente) != false, {
					size = ~srcPar.at(sFuente).at("size");
					tr = ~srcPar.at(sFuente).at("transpose");
					trD = ~srcPar.at(sFuente).at("rTranspose");
					gn = ~srcPar.at(sFuente).at("gain");
					hop = size / ~srcPar.at(sFuente).at("dens");
				});
			});

			if(~active && (~activas != nil), {
				grain = Synth(\simpleGrain,[
					\bufnum,
					~fuentes.at(fuente),
					\size, size,
					\tr, tr,
					\trD, trD,
					\pos, ~activas.at(selected,1),
					\gn, gn * ~glGain,
				], ~grGroup, addAction: 'addToHead');
			});
			(hop * 0.75 + (hop * 0.25).rand).wait;
	}, {
			0.1.wait;
		});
	});
});
)

//PLAY
//--------------------
~routine.play;
~routine.stop;
~arRoutine.play;
~arRoutine.stop;
~active = ~active.not;
~global = ~global.not;
~print = ~print.not;
~glGain = 1;
~arMode = 1;
~global;

(
~parameters["size"] = 0.4;
~parameters["transpose"] = 1;
~parameters["gain"] = 0.4;
~parameters["dens"] = 40;
~parameters["rTranspose"] = 0;
)

~parameters["transpose"] = 0.5;
~parameters["dens"] = 10;
~glGain = 1;
Env.linen.plot;
1.0.rand;
~parameters["dens"];

(
var nodes = 30;
var length = 3;
var features = 5;
var pos = Array.new();

pos = nodes.collect({Array.fill(features, {1.0.rand})});
~active = true;

{
	(nodes - 1).do({|i|
		pos.at(i).postln;
		100.do ({|j|
			var ind = j / 100;

			~lfoFunc.value(
				(pos.at(i).at(0) * (1 - ind)) + (pos.at(i+1).at(0) * ind),
				(pos.at(i).at(1) * (1 - ind)) + (pos.at(i+1).at(1) * ind),
				(pos.at(i).at(2) * (1 - ind)) + (pos.at(i+1).at(2) * ind),
				(pos.at(i).at(3) * (1 - ind)) + (pos.at(i+1).at(3) * ind),
				(pos.at(i).at(4) * (1 - ind)) + (pos.at(i+1).at(4) * ind)
			);


			/*
			~lfoFunc.value(
				//pos.at(i).at(0),
				//pos.at(i).at(1),
				//pos.at(i).at(2),
				pos.at(i).at(3),
				pos.at(i).at(4)
			);
			*/
			(length / 100).wait;
		});
		if(i == (nodes - 2), {~active = false});
	});
}.fork;
)


//orden: transpose, rTranspose, size, dens, gain

~fuentes.keys.do({|i| i.postln});
~srcPar.clear;
~setPar.value("C:\\Users\\Fabian\\Desktop\\fuentes\\guitarra\\g1.wav", 2, 0, 0.5, 40, 0.3);