using System;
using System.Collections.Generic;
using WakeMyPc;

public static class MouseTests {
    public static void Run() {
        var flags = new List<uint>(); long now = 0;
        var mouse = new RemoteMouse((x,y,data,flag) => { flags.Add(flag); return true; }, () => now);
        string prefix = "mouse:0123456789abcdef0123456789abcdef:";
        if (RemoteMouse.IsAllowed(prefix + "move:513:0")) throw new Exception("Unbounded motion");
        if (mouse.Execute(prefix + "left") != "input_ok" || flags[0] != 2 || flags[1] != 4) throw new Exception("Click order");
        if (mouse.Execute(prefix + "down") != "input_ok") throw new Exception("Drag failed");
        if (mouse.Execute("mouse:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:up") != "input_busy") throw new Exception("Wrong session released mouse");
        now = 1500; mouse.Expire();
        if (flags[flags.Count - 1] != 2) throw new Exception("Early release");
        mouse.Execute(prefix + "hold");
        now = 3400; mouse.Expire();
        if (flags[flags.Count - 1] != 2) throw new Exception("Heartbeat not respected");
        now = 3501; mouse.Expire();
        if (flags[flags.Count - 1] != 4) throw new Exception("Missing expiry release");
        if (mouse.Execute(prefix + "hold") != "input_expired") throw new Exception("Expired lease revived");
        mouse.Execute(prefix + "down"); mouse.Release();
        if (flags[flags.Count - 1] != 4) throw new Exception("Explicit release failed");
        int wheel = 0;
        var wheelMouse = new RemoteMouse((x,y,data,flag) => { wheel = data; return flag == 0x800; });
        if (wheelMouse.Execute(prefix + "wheel:-120") != "input_ok" || wheel != -120) throw new Exception("Wheel direction");
    }
}
