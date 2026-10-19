// Diagnostic only: record the summed browser output without a microphone.
// No sources, gains, playback rates or game state are changed.
(() => {
  const connect = AudioNode.prototype.connect;
  const disconnect = AudioNode.prototype.disconnect;
  const graphs = new WeakMap();
  const capture = {ready: false, error: '', sampleRate: 0, chunks: [], frames: 0};
  window.__jamAudioCapture = capture;
  const processor = `
    class JamCapture extends AudioWorkletProcessor {
      constructor() { super(); this.data = new Float32Array(8192); this.used = 0; }
      process(inputs) {
        const channels = inputs[0];
        if (!channels || !channels.length) return true;
        const left = channels[0], right = channels[1] || left;
        for (let index = 0; index < left.length; index++) {
          this.data[this.used++] = left[index];
          this.data[this.used++] = right[index];
          if (this.used === this.data.length) {
            this.port.postMessage(this.data.buffer, [this.data.buffer]);
            this.data = new Float32Array(8192); this.used = 0;
          }
        }
        return true;
      }
    }
    registerProcessor('jam-output-capture', JamCapture);
  `;

  function graph(context) {
    if (graphs.has(context)) return graphs.get(context);
    const mix = context.createGain();
    graphs.set(context, mix);
    connect.call(mix, context.destination);
    const url = URL.createObjectURL(new Blob([processor], {type: 'application/javascript'}));
    context.audioWorklet.addModule(url).then(() => {
      URL.revokeObjectURL(url);
      const recorder = new AudioWorkletNode(context, 'jam-output-capture');
      const silent = context.createGain();
      silent.gain.value = 0;
      connect.call(mix, recorder);
      connect.call(recorder, silent);
      connect.call(silent, context.destination);
      recorder.port.onmessage = event => {
        capture.chunks.push(new Uint8Array(event.data));
        capture.frames += event.data.byteLength / 8;
      };
      capture.sampleRate = context.sampleRate;
      capture.ready = true;
    }).catch(error => { capture.error = String(error); });
    return mix;
  }

  AudioNode.prototype.connect = function (destination, ...args) {
    if (destination === this.context.destination) {
      connect.call(this, graph(this.context), ...args);
      return destination;
    }
    return connect.call(this, destination, ...args);
  };
  AudioNode.prototype.disconnect = function (destination, ...args) {
    if (destination === this.context.destination && graphs.has(this.context)) {
      return disconnect.call(this, graphs.get(this.context), ...args);
    }
    return disconnect.apply(this, arguments);
  };
  capture.read = () => {
    const bytes = new Uint8Array(capture.chunks.reduce((total, chunk) => total + chunk.length, 0));
    let offset = 0;
    for (const chunk of capture.chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const parts = [];
    for (let index = 0; index < bytes.length; index += 32768) {
      parts.push(String.fromCharCode(...bytes.subarray(index, index + 32768)));
    }
    return {ready: capture.ready, error: capture.error, sampleRate: capture.sampleRate,
      frames: capture.frames, base64: btoa(parts.join(''))};
  };
})();
