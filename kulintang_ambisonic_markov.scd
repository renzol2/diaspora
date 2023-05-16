ServerOptions.outDevices
s.quit()
s.boot
Server.killAll

// Start everything
(
// Initialize server parameters
// s.options.outDevice = "ExtronScalerD";  // CAMIL
// s.options.outDevice = 'Audio Out';  // Studio A, Z
s.options.outDevice = 'Audio Out';
// s.options.outDevice = 'MOTU 828mk3 Hybrid';  // Studio X
ServerTree.removeAll;
s.options.numOutputBusChannels = 24;
s.options.numWireBufs = 256;
s.options.memSize = 2 ** 16;
~order = 3;
~nch = HoaOrder.new(~order).size;

s.newBusAllocators;
~bus = ();
~bus.monoIn = Bus.audio(s, 1);
~bus.stereoIn = Bus.audio(s, 2);
~bus.toZoom = Bus.audio(s, ~nch);
~bus.toDelay = Bus.audio(s, ~nch);
~bus.toRev = Bus.audio(s, ~nch);
~bus.toDec = Bus.audio(s, ~nch);

~directions = [
	// 1 - 5
	[36, 75], [108, 75], [180, 75], [-108, 75], [-36, 75],

	// 6 - 10
	[36, 20], [108, 20], [180, 20], [-108, 20], [-36, 20],

	// 11 - 15
	[0, -20], [72, -20], [144, -20], [-144, -20], [-72, -20],

	// 16 - 20
	[0, -75], [72, -75], [144, -75], [-144, -75], [-72, -75],
].degrad;

~eightChDirections = [
	[-45,0],  // FL
	[45,0],   // FR
	[-90,0],  // SL
	[90,0],   // SR
	[-135,0], // BL
	[135,0],  // BR
	[0,0],    // FC
	[180,0],  // BC
].degrad;

// decoder for dodecahedron loudspeaker array
~decoder = HoaMatrixDecoder.newModeMatch(
	directions: ~directions,
	beamShape: \energy,
	match: \energy,
	order: ~order
);

// decoder for 8 channel ring
~eightChDecoder = HoaMatrixDecoder.newModeMatch(
	directions: ~eightChDirections,
	beamShape: \energy,
	match: \energy,
	order: ~order
);

// Boot the server
s.waitForBoot({
	// Load the samples into buffers
	b = ();
	b.kulintang = PathName("samples/kulintang".resolveRelative).entries.collect({
		arg file;
		Buffer.readChannel(s, file.fullPath, channels:[0]);
	});

	// Define playback SynthDefs
	SynthDef.new(\play_rtt, {
		arg bufnum, amp, rate;
		var sig, env, rtt;

		sig = PlayBuf.ar(1, bufnum, rate: BufRateScale.ir(bufnum) * rate, doneAction: 2);

		sig = LPF.ar(sig, freq: 7000);  // rq should never go above 1.0

		sig = sig * amp;

		// Define rotate-tilt-tumble envelope
		rtt = [
			Env([\rot0.ir(0), \rot1.ir(0)], [\rttdur.ir(1)], [\rotcrv.ir(0)]).kr,
			Env([\til0.ir(0), \til1.ir(0)], [\rttdur.ir(1)], [\tilcrv.ir(0)]).kr,
			Env([\tum0.ir(0), \tum1.ir(0)], [\rttdur.ir(1)], [\tumcrv.ir(0)]).kr
		];

		// Encode and apply transformation
		sig = HoaEncodeDirection.ar(sig, \az.ir(0), \el.ir(0), AtkHoa.refRadius, ~order);
		sig = HoaRTT.ar(sig, rtt[0], rtt[1], rtt[2], ~order);

		Out.ar(\out.ir(0), sig);
	}).add;

	// Define delay effect
	SynthDef(\delay, {
		var sig, wet, apf, cmbf;
		sig = In.ar(\in.ir(0), ~nch);
		wet = LocalIn.ar(~nch) + sig;

		apf = AllpassC.ar(
			in: sig,
			maxdelaytime: 2,
			delaytime: SinOsc.kr(\lfoAllpassFreq.kr(1/10)).range(\minDelayTime.kr(0.02), \maxDelayTime.kr(2)),
			decaytime: VarLag.kr(\decayTime.kr(2), \decayTimeLag.kr(2), \decayTimeCurve.kr(5), \decayTimeWarp.kr(\lin)),
			// lag, varlag on args
			// provide argument for lagtime
		);

		cmbf = CombC.ar(
			in: sig,
			maxdelaytime: 2,
			delaytime: SinOsc.kr(\lfoCombFreq.kr(1/10)).range(\minDelayTime.kr(0.02), \maxDelayTime.kr(2)),
			decaytime: \decayTime.kr(2)
		);

		wet = apf + cmbf;

		LocalOut.ar(wet * VarLag.kr(\fb.kr(0.8), \fbLag.kr(2), \fbCurve.kr(5), \fbWarp.kr(\lin)));
		sig = (sig * \dryMix.kr(1.0)) + (wet * \wetMix.kr(0.2));
		sig = Limiter.ar(sig, 0.9);
		Out.ar(\out.ir(0), sig);
	}).add;

	SynthDef(\zoom, {
		var sig;
		sig = In.ar(\in.ir(0), ~nch);

		sig = HoaZoom.ar(
			in: sig,
			angle: VarLag.kr(\distortionAngle.kr(0), \distortionTime.kr(1)),
			theta: \theta.kr(0),
			phi: \phi.kr(0),
			radius: 1.5 // FIXME: change this?
		);

		Out.ar(\out.ir(0), sig);
	}).add;

	// https://github.com/khoin/dx463-final/blob/master/sdefs.sc#L150
	// RML: I wanted to try implementing Dattorro myself but not enough time :(
	SynthDef(\reverb, {
		arg in = 99,
		processMode = 0, // 0 uses Control values, 1 uses Bus for any param suffix Bus.
		gain = 0, mix = 0.07,
		processGain = 0, processGainBus = 99,
		preDelay = 0.001, bandwidth = 0.9,
		decayRate = 0.9, decayRateBus = 99,
		tailDensity = 0.3, damping = 0.003,
		excursionDepth = 0.2, excursionRate = 2,
		shimmerPitch = 1, shimmerPitchBus = 99,
		out = 0;

		// funcs
		var sampleRate = Server.default.sampleRate;
		var equalPower = {
			arg mix = 0.5;
			[(1-mix).sqrt, mix.sqrt];
		};
		var sampSec           = {
			arg numSamp, sampRate;
			numSamp / sampRate;
		};

		var gFacT60           = {
			arg delay, gFac;
			gFac.sign * (-3 * delay / log10(gFac.abs));

		};
		// some constant values
		// dSR = datorroSampleRate, sampleRate used in the paper.
		var dSR = 29761;
		var maxExcursion    = 32; // samples

		// values for prep part
		var preTankVals = [
			[0.75, 0.75, 0.625, 0.625], // gFacs
			sampSec.value([142, 107, 379, 277], dSR) // times
		].flop;

		// values for tank part
		// note that Dattorro flipped the sign of gFacs for the decaying APs,
		// I do that here so I don't worry about the signs later.
		var tankAP1GFac = -1 * tailDensity;
		var tankAP1Time = 672;
		var tankDel1    = sampSec.value(4453, dSR);
		var tankAP2GFac = (decayRate + 0.15).min(0.5).max(0.25);
		var tankAP2Time = sampSec.value(1800, dSR);
		var tankDel2    = sampSec.value(3720, dSR);

		var tankAP3GFac = tankAP1GFac;
		var tankAP3Time = 908;
		var tankDel3    = sampSec.value(4217, dSR);
		var tankAP4GFac = tankAP2GFac;
		var tankAP4Time = sampSec.value(2656, dSR);
		var tankDel4    = sampSec.value(3163, dSR);

		// Signals
		var dry     = In.ar(in, 2);
		var preTank = Silent.ar;
		var tank    = Silent.ar;
		var wetL    = Silent.ar;
		var wetR    = Silent.ar;
		var wet     = Silent.ar;
		var outs    = Silent.ar;

		// Params
		var pGain = Select.kr(processMode, [processGain.dbamp, Lag.kr(In.kr(processGainBus), 0.05)]);
		var sPitch = Select.kr(processMode, [shimmerPitch, Lag.kr(In.kr(shimmerPitchBus), 0.05)]);

		var fback;

		var dryAmp, wetAmp;
		#dryAmp, wetAmp = equalPower.value(mix);

		// proper mappings for params
		damping = (damping + (1 + (8 * damping))).log / (10.log); // somewhat better than linear
		bandwidth = 3.pow(bandwidth) - (1 + bandwidth);


		// ROUTINGS
		// make it mono
		preTank = (dry[0] + dry[1]) / 2;
		// pregain
		preTank = preTank * pGain;
		// predelay
		preTank = DelayC.ar(preTank, preDelay, preDelay);
		// lowpass
		preTank = LPF.ar(preTank, sampleRate / 2 * bandwidth);

		// 4 All-passes to diffuse inputs
		preTankVals.do({ arg pair; // 0: gFac, 1: time
			preTank = AllpassC.ar(preTank, pair[1], pair[1], gFacT60.value(pair[1], pair[0]));
		});

		fback = LocalIn.ar(1);

		// // Tank starts here
		// first branch
		tank  = AllpassC.ar(preTank + (decayRate * fback),
			maxdelaytime: sampSec.value(tankAP1Time + maxExcursion, dSR),
			delaytime: sampSec.value(tankAP1Time, dSR)
			+ (sampSec.value(maxExcursion, dSR) * excursionDepth * SinOsc.ar(excursionRate)),
			decaytime: gFacT60.value(sampSec.value(tankAP1Time, dSR), tankAP1GFac)
		);

		wetL = -0.6 * DelayC.ar(tank, sampSec.value(1990, dSR), sampSec.value(1990, dSR)) + wetL;
		wetR = 0.6 * tank + wetR;
		wetR = 0.6 * DelayC.ar(tank, sampSec.value(3300, dSR), sampSec.value(3300, dSR)) + wetR;
		tank = DelayC.ar(tank, tankDel1, tankDel1);
		tank = LPF.ar(tank, sampleRate / 2 * (1 - damping)) * decayRate;
		wetL = -0.6 * tank + wetL;
		tank = AllpassC.ar(tank, tankAP2Time, tankAP2Time, gFacT60.value(tankAP2Time, tankAP2GFac));
		wetR = -0.6 * tank + wetR;
		tank = DelayC.ar(tank, tankDel2, tankDel2);
		wetR = 0.6 * tank + wetR;

		// // second branch
		tank  = AllpassC.ar((tank * decayRate) + preTank,
			maxdelaytime: sampSec.value(tankAP3Time + maxExcursion, dSR),
			delaytime: sampSec.value(tankAP3Time, dSR)
			+ (sampSec.value(maxExcursion, dSR) * excursionDepth * 0.8 * SinOsc.ar(excursionRate * 0.8)),
			decaytime: gFacT60.value(sampSec.value(tankAP3Time, dSR), tankAP3GFac)
		);

		wetL = 0.6 * tank + wetL;
		wetL = 0.6 * DelayC.ar(tank, sampSec.value(2700, dSR), sampSec.value(2700, dSR)) + wetL;
		wetR = -0.6 * DelayC.ar(tank, sampSec.value(2100, dSR), sampSec.value(2100, dSR)) + wetR;
		tank = DelayC.ar(tank, tankDel3, tankDel3);
		tank = LPF.ar(tank, sampleRate / 2 * (1 - damping)) * decayRate;
		tank = AllpassC.ar(tank, tankAP4Time, tankAP4Time, gFacT60.value(tankAP4Time, tankAP4GFac));
		wetL = -0.6 * tank + wetL;
		wetR = -0.6 * DelayC.ar(tank, sampSec.value(200, dSR), sampSec.value(200, dSR)) + wetR;

		tank = DelayC.ar(tank, tankDel4, tankDel4);
		wetL = 0.6 * tank + wetL;

		tank = tank * decayRate;
		// // Sloppy Shimmering
		tank = PitchShift.ar(tank, pitchRatio: sPitch, mul: Select.kr(sPitch > 1, [1, 2.dbamp]));
		// // Tank ends here
		LocalOut.ar(tank);

		wet = [wetL, wetR];
		wet = HPF.ar(wet, 40); // Prevent lows from blowing up.

		outs = (dry * dryAmp) + (wet * wetAmp);
		outs = outs * gain.dbamp;

		Out.ar(out, outs);
	}).add;

	SynthDef(\dec, {
		var sig;
		sig = In.ar(\in.ir(0), ~nch);
		sig = HoaDecodeMatrix.ar(sig, ~decoder);

		Out.ar(\out.ir(0), sig);
	}).add;

	s.sync;

	~init = {
		~rev = Synth(\reverb, [in: ~bus.toRev, out: ~bus.toDec]);
		~delay = Synth(\delay, [in: ~bus.toDelay, out: ~bus.toRev]);
		~zoom = Synth(\zoom, [in: ~bus.toZoom, out: ~bus.toDelay]);
		// Change the output as necessary
		~dec = Synth(\dec, [in: ~bus.toDec, out: 0], s, \addToTail);
	};

	ServerTree.add(~init);
	ServerTree.run;
});
)

OSCdef.freeAll;

// Setup callback to listen to OscMessages from musx
(
~globalRtt = { rrand(pi.neg, pi) } ! 3;
~samplePlaybackRate = 1.0;
OSCdef.new(
	key: \kulintang,
	func: {
		|msg, time, from, port|
		var amp = msg[4] * exprand(0.05, 0.3);
		var gongIndex = msg[1] - 1;
		var rttShift = { exprand(pi/20, pi/10) * [1,-1].choose }.dup(3);
		var sus = exprand(0.1, 10);


		Synth.new(\play_rtt, [
			bufnum: b.kulintang[gongIndex],
			rate: ~samplePlaybackRate,
			amp: amp,
			atk: 0.001,
			rel: 1.0,
			rot0: ~globalRtt[0],
			rot1: ~globalRtt[0] + rttShift[0],
			til0: ~globalRtt[1],
			til1: ~globalRtt[1] + rttShift[1],
			tum0: ~globalRtt[2],
			tum1: ~globalRtt[2] + rttShift[2],
			rttdur: sus,
			az: rrand(pi.neg, pi),
			el: rrand(pi.neg, pi) / 2,
			out: ~bus.toZoom
		]);

		// shift
		~globalRtt[0] = ~globalRtt[0] + rttShift[0];
		~globalRtt[1] = ~globalRtt[1] + rttShift[1];
		~globalRtt[2] = ~globalRtt[2] + rttShift[2];
	},
	path: '/musx/kulintang',
	srcID: nil,
	recvPort: NetAddr.langPort
);
)

OSCdef.freeAll

(
~maxLfoFreq = 2;
OSCdef(\ios_osc_pad, {
	|msg|
	var padX, padY;
	padX = msg[1];
	padY = msg[2];
	[padX, padY].postln;
	~delay.set(\lfoAllpassFreq, padX.linexp(0.0, 1.0, 0.0001, ~maxLfoFreq));
	~delay.set(\lfoCombFreq, padY.linexp(0.0, 1.0, 0.0001, ~maxLfoFreq));
}, '/syntien/basic/1/touchpad1/press');

OSCdef(\dry_wet, {
	|msg|
	var sliderValue = msg[1];
	~delay.set(
		\dryMix, 1.0 - sliderValue,
		\wetMix, sliderValue,
	);
}, '/syntien/diaspora/1/dry_wet_slider');

OSCdef(\lfo_freq, {
	|msg|
	var padX = msg[1];
	var padY = msg[2];
	~delay.set(
		\lfoAllpassFreq, padX.linexp(0.0, 1.0, 0.0001, ~maxLfoFreq),
		\lfoCombFreq, padY.linexp(0.0, 1.0, 0.0001, ~maxLfoFreq),
	);
}, '/syntien/diaspora/1/lfo_freq_pad');

OSCdef(\feedback_decay, {
	|msg|
	var padX = msg[1];
	var padY = msg[2];
	~delay.set(
		\fb, padX,
		\fbLag, 0.1,
		\fbWarp, \sin,
		\decayTime, padY.linlin(0.0, 1.0, 0.0, 2.0),
	);
}, '/syntien/diaspora/1/feedback_decay_pad');

OSCdef(\delay_time, {
	|msg|
	var lowBound = msg[1];
	var highBound = msg[2];
	var minDelayTime = lowBound.linexp(0.0, 1.0, 0.001, 2);
	var maxDelayTime = highBound.linexp(0.0, 1.0, 0.001, 2);
	~delay.set(
		\minDelayTime, minDelayTime,
		\maxDelayTime, maxDelayTime,
	);
	"set min/max delay times".ccatArgs(minDelayTime, maxDelayTime).postln;
}, '/syntien/diaspora/1/delay_time_range_slider');

OSCdef(\playback_rate, {
	|msg|
	~samplePlaybackRate = msg[1].linlin(0.0, 1.0, 0.05, 2.0);
	"set playback rate to ".catArgs(~samplePlaybackRate).postln;
}, '/syntien/diaspora/1/playback_rate_slider');

~zoomTheta = 0;
OSCdef(\zoom_theta, {
	|msg|
	~zoomTheta = msg[1].linlin(0.0, 1.0, 0.0, 2pi);
	"set zoom azimuth angle to ".catArgs(~zoomTheta).postln;
}, '/syntien/diaspora/1/zoom_theta_slider');

~zoomPhi = 0;
OSCdef(\zoom_phi, {
	|msg|
	~zoomPhi = msg[1].linlin(0.0, 1.0, -pi/2, pi/2);
	"set zoom elevation angle to ".catArgs(~zoomPhi).postln;
}, '/syntien/diaspora/1/zoom_phi_slider');

OSCdef(\zoom, {
	|msg|
	if ( msg[1] == 1,
		{
			'initiate zoom'.postln;
			~zoom.set(
				\distortionAngle, pi/4,
				\distortionTime, 4,
				\theta, ~zoomTheta,
				\phi, ~zoomPhi,
			);
		}
	)
}, '/syntien/diaspora/1/zoom_button');

OSCdef(\zoom_reset, {
	|msg|
	if ( msg[1] == 1,
		{
			'reset zoom'.postln;
			~zoom.set(
				\distortionAngle, 0,
				\distortionTime, 4,
			);
		}
	)
}, '/syntien/diaspora/1/zoom_reset_button');
)

// Testing single parameters
~delay.set(\wetMix, 0.7);
~delay.set(\wetMix, 0.0);
~delay.set(\dryMix, 0.7);
~delay.set(\dryMix, 0.0);
~delay.set(\fb, 0.1, \fbLag, 1, \fbCurve, 5, \fbWarp, \lin);
~delay.set(\decayTime, 0.01, \decayTimeLag, 2, \decayTimeCurve, 5, \decayTimeWarp, \lin);
~delay.set(\lfoAllpassFreq, 0.1);
~delay.set(\lfoCombFreq, 0.1);
~delay.set(\minDelayTime, 0.02);
~delay.set(\maxDelayTime, 1);

(
~delay.set(
	\lfoAllpassFreq, rrand(0.01, 0.2),
	\lfoCombFreq, rrand(0.01, 0.2),
	\minDelayTime, 0.001,
	\maxDelayTime, 2,
	\decayTime, 2,
);
)

(
~delay.set(
	\lfoAllPassFreq, rrand(0.001, 0.002),
	\lfoCombFreq, rrand(0.001, 0.002),
	\minDelayTime, 0.02,
	\maxDelayTime, 0.04,
	\decayTime, 0.02,
);
)

(
~delay.set(
	\lfoAllPassFreq, 0.1,
	\lfoCombFreq, 0.2,
	\minDelayTime, 0.001,
	\maxDelayTime, 0.1
);
)

(
~zoom.set(
	\distortionAngle, 0,
	\distortionTime, 10,
	\theta, pi,
	\phi, 0,
);
)

// Show scope
s.scope;

// Record channels
s.record(numChannels: 8);
s.stopRecording;

// Stop server
s.quit();
