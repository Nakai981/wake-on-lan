using System;
using System.Diagnostics;

namespace WakeMyPc {
    // Runs on the Agent UI thread. Injection and clock are replaceable in tests.
    public sealed class RemoteMouse {
        readonly Func<int, int, int, uint, bool> emit;
        readonly Func<long> now;
        string owner;
        long deadline;
        public RemoteMouse(Func<int, int, int, uint, bool> sink, Func<long> clock = null) {
            emit = sink; now = clock ?? (() => Stopwatch.GetTimestamp() * 1000 / Stopwatch.Frequency);
        }
        public static bool IsAllowed(string command) {
            var p = command.Split(':'); int x, y;
            if (p.Length < 3 || p[0] != "mouse" || !AgentServer.IsHex(p[1], 32)) return false;
            if (p.Length == 3) return p[2] == "left" || p[2] == "right" || p[2] == "down" || p[2] == "up" || p[2] == "hold";
            if (p.Length == 5 && p[2] == "move") return int.TryParse(p[3], out x) && int.TryParse(p[4], out y) && x >= -512 && x <= 512 && y >= -512 && y <= 512;
            return p.Length == 4 && p[2] == "wheel" && int.TryParse(p[3], out x) && x >= -1200 && x <= 1200;
        }
        public void Release() {
            if (owner == null) return;
            // Keep ownership until release succeeds, allowing the timer to retry.
            if (emit(0, 0, 0, 4)) owner = null;
        }
        public void Expire() { if (owner != null && now() >= deadline) Release(); }
        public string Execute(string command) {
            if (!IsAllowed(command)) return "unsupported";
            Expire();
            var p = command.Split(':'); var session = p[1]; var action = p[2];
            if (owner != null && owner != session) return "input_busy";
            if (action == "up") { Release(); return owner == null ? "input_ok" : "input_failed"; }
            if (action == "hold") {
                if (owner != session) return "input_expired";
                deadline = now() + 2000; return "input_ok";
            }
            if (action == "down") {
                if (owner == null) {
                    // Record before injection so even partial failures trigger a release.
                    owner = session;
                    if (!emit(0, 0, 0, 2)) { Release(); return "input_failed"; }
                }
                deadline = now() + 2000; return "input_ok";
            }
            bool ok;
            if (action == "move") ok = emit(int.Parse(p[3]), int.Parse(p[4]), 0, 1);
            else if (action == "wheel") ok = emit(0, 0, int.Parse(p[3]), 0x800);
            else {
                if (owner != null) return "input_busy";
                uint down = action == "left" ? 2u : 8u, up = action == "left" ? 4u : 16u;
                ok = emit(0, 0, 0, down);
                bool released = emit(0, 0, 0, up);
                if (!released) emit(0, 0, 0, up);
                ok = ok && released;
            }
            return ok ? "input_ok" : "input_failed";
        }
    }
}
