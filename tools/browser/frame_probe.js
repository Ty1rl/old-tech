// Bounded browser frame timing; separate from audio audibility/source telemetry.
(() => {
  let previous = 0, durations = [], longTasks = 0, longestTask = 0;
  const frame = now => {
    if (previous && durations.length < 1000) durations.push(now - previous);
    previous = now;
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
  if (PerformanceObserver.supportedEntryTypes?.includes('longtask')) {
    new PerformanceObserver(list => {
      for (const entry of list.getEntries()) {
        longTasks++;
        longestTask = Math.max(longestTask, entry.duration);
      }
    }).observe({type: 'longtask', buffered: true});
  }
  window.__readFrameAudit = () => {
    const sorted = durations.sort((a, b) => a - b);
    durations = [];
    const percentile = fraction => sorted.length
      ? sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)] : 0;
    return {
      frame_window_samples: sorted.length,
      frame_window_median_ms: percentile(.5),
      frame_window_p95_ms: percentile(.95),
      frame_window_max_ms: sorted.at(-1) || 0,
      frame_window_over_50ms: sorted.filter(value => value > 50).length,
      long_tasks_count: longTasks,
      long_tasks_max_ms: longestTask,
    };
  };
})();
