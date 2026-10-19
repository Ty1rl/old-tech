// Observe the real Web Audio graph without retaining sources or changing playback.
window.__webAudit = {created: 0, starts: 0, stops: 0, ended: 0, frames: 0,
  maxFrameGapMs: 0, audiblePeak: 0, contexts: [], analysers: []};
(() => {
  const audit = window.__webAudit;
  const makeSource = BaseAudioContext.prototype.createBufferSource;
  BaseAudioContext.prototype.createBufferSource = function (...args) {
    const source = makeSource.apply(this, args);
    audit.created++;
    if (!audit.contexts.includes(this)) audit.contexts.push(this);
    const start = source.start.bind(source), stop = source.stop.bind(source);
    source.start = (...args) => { audit.starts++; return start(...args); };
    source.stop = (...args) => { audit.stops++; return stop(...args); };
    source.addEventListener('ended', () => audit.ended++, {once: true});
    return source;
  };
  const connect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (destination, ...args) {
    if (destination instanceof AudioDestinationNode && audit.analysers.length < 8) {
      const analyser = this.context.createAnalyser();
      analyser.fftSize = 1024;
      audit.analysers.push(analyser);
      connect.call(this, analyser);
      connect.call(analyser, destination);
      return destination;
    }
    return connect.call(this, destination, ...args);
  };
  let previous = performance.now();
  const frame = now => {
    audit.maxFrameGapMs = Math.max(audit.maxFrameGapMs, now - previous);
    previous = now; audit.frames++; requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
  window.__readWebAudit = () => {
    let peak = 0;
    for (const analyser of audit.analysers) {
      const samples = new Float32Array(analyser.fftSize);
      analyser.getFloatTimeDomainData(samples);
      for (const value of samples) peak = Math.max(peak, Math.abs(value));
    }
    audit.audiblePeak = Math.max(audit.audiblePeak, peak);
    return {created: audit.created, starts: audit.starts, stops: audit.stops,
      ended: audit.ended, frames: audit.frames, maxFrameGapMs: audit.maxFrameGapMs,
      audiblePeak: audit.audiblePeak, outputPeak: peak,
      audioStates: [...new Set([...audit.contexts, ...audit.analysers.map(node => node.context)])]
        .map(context => context.state)};
  };
})();
