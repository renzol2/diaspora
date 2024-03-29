# Diaspora (2023)

*Diaspora* is an effects-driven, 8-channel fixed media electroacoustic composition featuring samples of the kulintang.

You can listen to *Diaspora* (2023) on [SoundCloud](https://soundcloud.com/renzomledesma/diaspora) or [Bandcamp](https://renzomledesma.bandcamp.com/track/diaspora).

## Background

*Diaspora* is an experimental music composition that serves as an expression of my experience growing up in the Filipino diaspora, disconnected from my parents’ life in the Philippines. It is also a direct product of my personal journey learning about Filipino culture during college.

This piece involves recorded samples of the *kulintang*, a percussive instrument consisting of eight bossed gongs commonly played in the southern regions of the Philippines. The samples were recorded from a kulintang donated to the [Philippine Student Association at UIUC](https://www.psauiuc.org/) for use in performances and recordings by their cultural dancing group, [PSA Barkada](https://www.psauiuc.org/cultural-chair/).

Different cultures across the Philippines have distinct styles and traditions for playing the kulintang. The style of kulintang music from Maguindanao, a province in the southern island of Mindanao in the Philippines, is the most cited in ethnomusicology work and contemporary practitioners.

## Implementation

The implementation of *Diaspora* involves the triggering of samples determined by Markov systems built from Maguindanaon kulintang transcriptions recorded by musicologist Dr. Kristina Benitez and kulintang master Prof. Aga Mayo Butocan. I developed the Markov systems using Professor Heinrich Taube’s [`musx`](https://pypi.org/project/musx/) algorithmic composition software library, with audio processing in [SuperCollider](https://supercollider.github.io/) and effects manipulation in [Syntien](https://blackislandaudio.com/products/syntien).

My work towards integrating kulintang with `musx` began in the fall of 2021 as my final project for MUS 305, a class on algorithmic composition with the `musx` package taught by Professor Heinrich Taube. You can view the original project [here](https://github.com/renzol2/mus305-fall21/tree/master/12_finalproject).

The following files comprise the kulintang score generation:

- `transcriptions/`, which contains full transcriptions of kulintang improvisations from Dr. Kristina Benitez
- `scosc.py`, which contains a class for sending OSC messages to SuperCollider
- `kulintang.py`, which uses `musx` to generate transition tables using Markov chains from the kulintang transcriptions and sends the data over OSC to SuperCollider

Finally, `kulintang_ambisonic_markov.scd` receives the OSC data from Python and handles ssample loading, multichannel encoding/decoding using the [Ambisonic Toolkit for Supercollider](https://www.ambisonictoolkit.net/documentation/supercollider/), and audio effects processing.

## Installation

The installation of this piece requires the following software:

- Python 3.9 and `musx`
- SuperCollider
- SuperCollider Ambisonic Toolkit
- Syntien iOS App

TODO: write in detail how to (theoretically) run this piece

