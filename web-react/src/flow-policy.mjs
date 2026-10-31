export const COMMAND_WAIT_MS = 20_000;
export function startupWaitMs(seconds = 20) {
  const value = Number(seconds);
  return Number.isInteger(value) && value >= 10 && value <= 30 ? value * 1000 : COMMAND_WAIT_MS;
}
export function scheduleStateCheck(startedAt, check, waitMs = COMMAND_WAIT_MS) {
  return setTimeout(check, Math.max(0, startedAt + waitMs - Date.now()));
}
export function wakeObservationPhase(responding, readyAt, now = Date.now()) {
  if (responding) return 'online';
  return now < readyAt ? 'booting' : 'unknown';
}
export function validPowerAuthorization(proof, pc, command, now = Date.now()) {
  return !!proof && ['sleep', 'shutdown'].includes(command) && proof.id === pc.id &&
    proof.ip === pc.ip && proof.mac === pc.mac && proof.command === command &&
    now >= proof.at && now - proof.at <= 120_000;
}
