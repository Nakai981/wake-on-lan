using System;
using System.Globalization;

namespace WakeMyPc {
    // Accessed on the UI thread; this class never invokes a power API.
    public sealed class PowerDelay {
        public string Action { get; private set; }
        public DateTime Deadline { get; private set; }

        public static bool IsAllowed(string command) {
            string action; int seconds;
            return Parse(command, out action, out seconds);
        }
        static bool Parse(string command, out string action, out int seconds) {
            action = null; seconds = 0;
            var parts = command.Split(':');
            if (parts.Length != 3 || parts[0] != "power" ||
                (parts[1] != "sleep" && parts[1] != "shutdown") ||
                parts[2].Length < 1 || parts[2].Length > 5 || parts[2][0] == '0') return false;
            foreach (char c in parts[2]) if (c < '0' || c > '9') return false;
            if (!int.TryParse(parts[2], NumberStyles.None, CultureInfo.InvariantCulture, out seconds) ||
                seconds < 1 || seconds > 86400) return false;
            action = parts[1]; return true;
        }
        public string Handle(string command, DateTime now) {
            if (command == "cancel") { Cancel(); return "cancelled"; }
            string action; int seconds;
            if (command == "sleep" || command == "shutdown") {
                action = command; seconds = 10;
            } else if (!Parse(command, out action, out seconds)) return "unsupported";
            if (Action != null) return "busy";
            Action = action; Deadline = now.AddSeconds(seconds); return "accepted";
        }
        public void Cancel() { Action = null; }
        public string TakeDue(DateTime now) {
            if (Action == null || now < Deadline) return null;
            var action = Action; Cancel(); return action;
        }
    }
}
