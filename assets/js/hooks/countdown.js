// Counts down to an auction's end time in the browser, with no server ticks.
//
// Usage: <p id="..." phx-hook="Countdown" phx-update="ignore" data-ends-at="ISO8601">
//
// It re-reads data-ends-at on every tick, so a new end time from the server
// (an anti-snipe extension) shows up right away. phx-update="ignore" keeps
// LiveView from overwriting the text this hook writes.

const Countdown = {
  mounted() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  },

  destroyed() {
    clearInterval(this.timer)
  },

  tick() {
    const ms = new Date(this.el.dataset.endsAt) - Date.now()
    this.el.textContent = ms > 0 ? `ends in ${formatRemaining(ms)}` : "ending…"
  },
}

function formatRemaining(ms) {
  const total = Math.floor(ms / 1000)
  const days = Math.floor(total / 86400)
  const hours = Math.floor((total % 86400) / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60

  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${minutes}m`
  if (minutes > 0) return `${minutes}m ${seconds}s`
  return `${seconds}s`
}

export default Countdown
