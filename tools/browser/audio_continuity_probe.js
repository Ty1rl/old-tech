(() => {
  const state = {
    contexts: [],
    created: 0,
    starts: 0,
    stops: 0,
    ended: 0,
    frames: 0,
    lastFrame: 0,
    maxFrameGapMs: 0,
    frameStallsOver50Ms: 0,
    frameStallsOver100Ms: 0,
    audiblePeak: 0,
    outputPeak: 0,
    analysers: [],
    streamRingBufferFrames: 0,
    streamRingBufferMs: 0,
    streamChunksSent: 0,
    lastChunkTime: 0,
    maxChunkGapMs: 0,
    lastChunkPeak: 0,
    workletTotalQuanta: 0,
    workletUnderflowQuanta: 0,
    workletUnderflowMs: 0,
    audibleUnderflowQuanta: 0,
    audibleUnderflowMs: 0,
    audibleUnderflowEvents: 0,
    currentAudibleUnderflowMs: 0,
    maxAudibleDropoutMs: 0,
    inAudibleUnderflow: false,
  };

  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (Ctx) {
    const Orig = Ctx;
    const Wrapped = function (...args) {
      const ctx = new Orig(...args);
      state.contexts.push(ctx);
      return ctx;
    };
    Wrapped.prototype = Orig.prototype;
    Object.setPrototypeOf(Wrapped, Orig);
    window.AudioContext = Wrapped;
    if (window.webkitAudioContext) window.webkitAudioContext = Wrapped;
  }

  if (window.AudioWorklet && AudioWorklet.prototype.addModule) {
    const origAddModule = AudioWorklet.prototype.addModule;
    AudioWorklet.prototype.addModule = async function (moduleUrl, options) {
      const urlStr = String(moduleUrl || '');
      if (urlStr.includes('audio.worklet.js') && !urlStr.includes('position')) {
        try {
          const resp = await fetch(urlStr);
          const src = await resp.text();
          const commentTarget = "// this.port.postMessage('Output buffer has not enough frames! Skipping output frame.');";
          if (src.includes(commentTarget)) {
            const patched = src.replace(
              commentTarget,
              "this.port.postMessage({ 'cmd': '__jam_underflow', 'data': chunk });"
            );
            const blob = new Blob([patched], { type: 'application/javascript' });
            const blobUrl = URL.createObjectURL(blob);
            return await origAddModule.call(this, blobUrl, options);
          }
        } catch (_err) {
          // Fall back to unmodified worklet URL if fetch fails.
        }
      }
      return origAddModule.call(this, moduleUrl, options);
    };
  }

  if (window.AudioWorkletNode) {
    const OrigWorkletNode = window.AudioWorkletNode;
    const WrappedWorkletNode = function (context, name, options) {
      const node = new OrigWorkletNode(context, name, options);
      if (name === 'godot-processor' && node.port) {
        const sampleRate = (context && context.sampleRate) ? context.sampleRate : 48000;
        const origPostMessage = node.port.postMessage.bind(node.port);
        node.port.postMessage = function (msg, ...rest) {
          if (msg && msg.cmd === 'start_nothreads' && Array.isArray(msg.data) && msg.data[0]) {
            const floats = msg.data[0].length || 0;
            state.streamRingBufferFrames = Math.floor(floats / 2);
            state.streamRingBufferMs = Number(((state.streamRingBufferFrames / sampleRate) * 1000).toFixed(2));
          } else if (msg && msg.cmd === 'chunk' && msg.data) {
            const now = performance.now();
            const buf = msg.data;
            let peak = 0;
            for (let i = 0; i < buf.length; i += 4) {
              const v = Math.abs(buf[i]);
              if (v > peak) peak = v;
            }
            if (state.lastChunkTime > 0 && state.lastChunkPeak > 0.0005) {
              const gap = now - state.lastChunkTime;
              if (gap > state.maxChunkGapMs) state.maxChunkGapMs = Number(gap.toFixed(2));
            }
            state.lastChunkTime = now;
            state.lastChunkPeak = peak;
            state.streamChunksSent += 1;
          }
          return origPostMessage(msg, ...rest);
        };

        const origPortDesc = Object.getOwnPropertyDescriptor(MessagePort.prototype, 'onmessage');
        Object.defineProperty(node.port, 'onmessage', {
          configurable: true,
          enumerable: true,
          get() {
            return origPortDesc ? origPortDesc.get.call(this) : null;
          },
          set(fn) {
            if (!origPortDesc) return;
            if (typeof fn !== 'function') {
              origPortDesc.set.call(this, fn);
              return;
            }
            origPortDesc.set.call(this, function (event) {
              const data = event && event.data;
              const chunkFloats = (data && typeof data.data === 'number') ? data.data : 256;
              const quantumMs = ((chunkFloats / 2) / sampleRate) * 1000;
              if (data && data.cmd === '__jam_underflow') {
                state.workletTotalQuanta += 1;
                state.workletUnderflowQuanta += 1;
                state.workletUnderflowMs += quantumMs;
                if (state.lastChunkPeak > 0.0005) {
                  state.audibleUnderflowQuanta += 1;
                  state.audibleUnderflowMs += quantumMs;
                  state.currentAudibleUnderflowMs += quantumMs;
                  if (!state.inAudibleUnderflow) {
                    state.inAudibleUnderflow = true;
                    state.audibleUnderflowEvents += 1;
                  }
                  if (state.currentAudibleUnderflowMs > state.maxAudibleDropoutMs) {
                    state.maxAudibleDropoutMs = state.currentAudibleUnderflowMs;
                  }
                }
                return;
              }
              if (data && data.cmd === 'read') {
                state.workletTotalQuanta += 1;
                state.inAudibleUnderflow = false;
                state.currentAudibleUnderflowMs = 0;
              }
              return fn.call(this, event);
            });
          },
        });
      }
      return node;
    };
    WrappedWorkletNode.prototype = OrigWorkletNode.prototype;
    Object.setPrototypeOf(WrappedWorkletNode, OrigWorkletNode);
    window.AudioWorkletNode = WrappedWorkletNode;
  }

  if (window.BaseAudioContext && BaseAudioContext.prototype.createBuffer) {
    const origCreateBuffer = BaseAudioContext.prototype.createBuffer;
    BaseAudioContext.prototype.createBuffer = function (channels, length, sampleRate) {
      const buf = origCreateBuffer.call(this, channels, length, sampleRate);
      state.buffersCreated = (state.buffersCreated || 0) + 1;
      state.bufferBytesAllocated = (state.bufferBytesAllocated || 0) + (Number(channels || 2) * Number(length || 0) * 4);
      return buf;
    };
  }

  if (window.BaseAudioContext && BaseAudioContext.prototype.createBufferSource) {
    const origCreate = BaseAudioContext.prototype.createBufferSource;
    BaseAudioContext.prototype.createBufferSource = function (...args) {
      const node = origCreate.apply(this, args);
      state.created += 1;
      let activeTracked = false;
      node.addEventListener('ended', () => {
        state.ended += 1;
        if (activeTracked) {
          activeTracked = false;
          state.activeSources = Math.max(0, (state.activeSources || 0) - 1);
        }
      });
      const origStart = node.start;
      node.start = function (...startArgs) {
        state.starts += 1;
        if (!activeTracked) {
          activeTracked = true;
          state.activeSources = (state.activeSources || 0) + 1;
        }
        try {
          if (node.buffer && node.buffer.length) {
            const data = node.buffer.getChannelData(0);
            const step = Math.max(1, Math.floor(data.length / 512));
            for (let i = 0; i < data.length; i += step) {
              state.audiblePeak = Math.max(state.audiblePeak, Math.abs(data[i]));
            }
          }
        } catch (_err) {}
        return origStart.apply(this, startArgs);
      };
      const origStop = node.stop;
      node.stop = function (...stopArgs) {
        state.stops += 1;
        if (activeTracked) {
          activeTracked = false;
          state.activeSources = Math.max(0, (state.activeSources || 0) - 1);
        }
        return origStop.apply(this, stopArgs);
      };
      return node;
    };
  }

  if (window.AudioNode && AudioNode.prototype.connect) {
    const origConnect = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (dest, ...rest) {
      try {
        if (dest && this.context && dest === this.context.destination && !this.__jamTapped) {
          this.__jamTapped = true;
          const analyser = this.context.createAnalyser();
          analyser.fftSize = 256;
          origConnect.call(this, analyser);
          state.analysers.push(analyser);
        }
      } catch (_err) {}
      return origConnect.call(this, dest, ...rest);
    };
  }

  function sampleOutput() {
    const data = new Float32Array(256);
    let current = 0;
    for (const analyser of state.analysers) {
      try {
        analyser.getFloatTimeDomainData(data);
        for (let i = 0; i < data.length; i += 1) {
          const v = Math.abs(data[i]);
          current = Math.max(current, v);
          state.audiblePeak = Math.max(state.audiblePeak, v);
        }
      } catch (_err) {}
    }
    state.outputPeak = current;
  }

  function getSampleStats() {
    return {
      activeSampleNodes: state.activeSources || 0,
      registeredSamples: state.buffersCreated || 0,
      registeredSampleBytes: state.bufferBytesAllocated || 0,
    };
  }

  function tick(now) {
    if (state.lastFrame) {
      const gap = now - state.lastFrame;
      state.maxFrameGapMs = Math.max(state.maxFrameGapMs, gap);
      if (gap > 50) state.frameStallsOver50Ms += 1;
      if (gap > 100) state.frameStallsOver100Ms += 1;
    }
    state.lastFrame = now;
    state.frames += 1;
    sampleOutput();
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);

  window.__jamAudioProbe = {
    snapshot() {
      sampleOutput();
      const sampleStats = getSampleStats();
      return {
        created: state.created,
        starts: state.starts,
        stops: state.stops,
        ended: state.ended,
        frames: state.frames,
        maxFrameGapMs: Number(state.maxFrameGapMs.toFixed(2)),
        frameStallsOver50Ms: state.frameStallsOver50Ms,
        frameStallsOver100Ms: state.frameStallsOver100Ms,
        audiblePeak: state.audiblePeak,
        outputPeak: state.outputPeak,
        audioStates: state.contexts.map((c) => c.state),
        streamRingBufferFrames: state.streamRingBufferFrames,
        streamRingBufferMs: state.streamRingBufferMs,
        streamChunksSent: state.streamChunksSent,
        maxChunkGapMs: state.maxChunkGapMs,
        workletTotalQuanta: state.workletTotalQuanta,
        workletUnderflowQuanta: state.workletUnderflowQuanta,
        workletUnderflowMs: Number(state.workletUnderflowMs.toFixed(2)),
        audibleUnderflowQuanta: state.audibleUnderflowQuanta,
        audibleUnderflowMs: Number(state.audibleUnderflowMs.toFixed(2)),
        audibleUnderflowEvents: state.audibleUnderflowEvents,
        maxAudibleDropoutMs: Number(state.maxAudibleDropoutMs.toFixed(2)),
        activeSampleNodes: sampleStats.activeSampleNodes,
        registeredSamples: sampleStats.registeredSamples,
        registeredSampleBytes: sampleStats.registeredSampleBytes,
      };
    },
  };
})();
