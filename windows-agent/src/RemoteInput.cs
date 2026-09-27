using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace WakeMyPc {
    public static class RemoteInput {
        [StructLayout(LayoutKind.Sequential)] struct Keyboard { public ushort Vk, Scan; public uint Flags, Time; public IntPtr Extra; }
        [StructLayout(LayoutKind.Sequential)] struct Mouse { public int X, Y; public uint Data, Flags, Time; public IntPtr Extra; }
        [StructLayout(LayoutKind.Explicit)] struct Union { [FieldOffset(0)] public Keyboard Key; [FieldOffset(0)] public Mouse Mouse; }
        [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public Union Data; }
        [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, Input[] events, int size);
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
        static readonly ushort[] Modifiers = { 0x11, 0x12, 0x10, 0x5B };
        public static bool MouseEvent(int x, int y, int data, uint flags) {
            var input = new Input { Type = 0, Data = new Union { Mouse = new Mouse { X = x, Y = y, Data = unchecked((uint)data), Flags = flags } } };
            return SendInput(1, new[] { input }, Marshal.SizeOf(typeof(Input))) == 1;
        }
        public static bool IsAllowed(string command) {
            int mask, key; string text;
            return Parse(command, out mask, out key, out text);
        }
        static bool Parse(string command, out int mask, out int key, out string text) {
            mask = key = 0; text = null;
            if (command.StartsWith("text:", StringComparison.Ordinal)) {
                try {
                    var bytes = Convert.FromBase64String(command.Substring(5));
                    if (bytes.Length == 0 || bytes.Length > 240) return false;
                    text = new UTF8Encoding(false, true).GetString(bytes);
                    foreach (char c in text) if (char.IsControl(c)) return false;
                    return true;
                } catch { return false; }
            }
            var parts = command.Split(':');
            if (parts.Length != 3 || parts[0] != "key" || !int.TryParse(parts[1], out mask) || !int.TryParse(parts[2], out key) || mask < 0 || mask > 15) return false;
            return (key >= 0x30 && key <= 0x5A) || (key >= 0x70 && key <= 0x7B) || (key >= 0xAD && key <= 0xB3) || key == 8 || key == 9 || key == 13 || key == 27 || key == 32 || (key >= 37 && key <= 40) || key == 46;
        }
        static Input Event(ushort key, ushort scan, uint flags) {
            return new Input { Type = 1, Data = new Union { Key = new Keyboard { Vk = key, Scan = scan, Flags = flags } } };
        }
        public static string Execute(string command) {
            int mask, key; string text;
            if (!Parse(command, out mask, out key, out text)) return "unsupported";
            // Do not interfere with keys physically held by the PC user.
            foreach (var mod in new int[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }) if ((GetAsyncKeyState(mod) & 0x8000) != 0) return "input_busy";
            var events = new List<Input>();
            if (text != null) {
                foreach (char c in text) { events.Add(Event(0, c, 4)); events.Add(Event(0, c, 6)); }
            } else {
                for (int i = 0; i < 4; i++) if ((mask & (1 << i)) != 0) events.Add(Event(Modifiers[i], 0, i == 3 ? 1u : 0u));
                uint extended = (key >= 37 && key <= 40) || key == 46 || key >= 0xAD ? 1u : 0u;
                events.Add(Event((ushort)key, 0, extended)); events.Add(Event((ushort)key, 0, extended | 2));
                for (int i = 3; i >= 0; i--) if ((mask & (1 << i)) != 0) events.Add(Event(Modifiers[i], 0, (i == 3 ? 1u : 0u) | 2));
            }
            var sent = SendInput((uint)events.Count, events.ToArray(), Marshal.SizeOf(typeof(Input)));
            if (sent == events.Count) return "input_ok";
            // Release any potentially inserted keys, never retain a modifier across requests.
            var releases = new List<Input>();
            foreach (var e in events) if ((e.Data.Key.Flags & 2) != 0) releases.Add(e);
            SendInput((uint)releases.Count, releases.ToArray(), Marshal.SizeOf(typeof(Input)));
            return "input_failed";
        }
    }
}
