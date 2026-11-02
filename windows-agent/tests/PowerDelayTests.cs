using System;
using WakeMyPc;

public static class PowerDelayTests {
    static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
    public static void Main() {
        var now = new DateTime(2026, 11, 3, 0, 0, 0, DateTimeKind.Utc);
        foreach (string action in new [] { "sleep", "shutdown" }) {
            var pending = new PowerDelay();
            Check(pending.Handle("power:" + action + ":30", now) == "accepted", "Not accepted");
            Check(pending.Deadline == now.AddSeconds(30), "Wrong delay");
            Check(pending.TakeDue(now.AddSeconds(10)) == null, "Executed at old default");
            Check(pending.Handle("sleep", now) == "busy", "Overwrote pending command");
            Check(pending.TakeDue(now.AddSeconds(30)) == action, "Not due at configured time");
            Check(pending.TakeDue(now.AddSeconds(31)) == null, "Executed twice");
            Check(pending.Handle(action, now) == "accepted", "Legacy command rejected");
            Check(pending.Deadline == now.AddSeconds(10), "Legacy default changed");
            Check(pending.Handle("cancel", now) == "cancelled", "Cancel failed");
            Check(pending.TakeDue(now.AddSeconds(20)) == null, "Cancelled command executed");
            Check(PowerDelay.IsAllowed("power:" + action + ":1"), "Min rejected");
            Check(PowerDelay.IsAllowed("power:" + action + ":86400"), "Max rejected");
        }
        foreach (string command in new [] { "power:sleep:0", "power:sleep:-1", "power:sleep:86401",
            "power:sleep:01", "power:reboot:30", "power:shutdown:30:extra" }) {
            Check(!PowerDelay.IsAllowed(command), "Allowed invalid command");
            Check(new PowerDelay().Handle(command, now) == "unsupported", "Executed invalid command");
        }
        Console.WriteLine("Power delay tests passed (no power APIs invoked).");
    }
}
