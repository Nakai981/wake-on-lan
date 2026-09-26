using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace WakeMyPc {
    // One challenge and one authenticated command per connection. No shell text
    // is accepted. Client nonce binds the signed reply to this request.
    public sealed class AgentServer : IDisposable {
        readonly TcpListener listener;
        readonly Func<byte[]> key;
        readonly Func<string, string> execute;
        readonly SemaphoreSlim slots = new SemaphoreSlim(12);
        volatile bool stopped;
        public AgentServer(IPAddress address, int port, Func<byte[]> secret, Func<string, string> handler) {
            listener = new TcpListener(address, port); key = secret; execute = handler;
        }
        public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
        public void Start() { listener.Start(12); Task.Run((Action)AcceptLoop); }
        void AcceptLoop() {
            while (!stopped) {
                TcpClient client;
                try { client = listener.AcceptTcpClient(); } catch { if (stopped) return; continue; }
                if (!slots.Wait(0)) { client.Close(); continue; }
                Task.Run(() => { try { Handle(client); } catch { } finally { client.Close(); slots.Release(); } });
            }
        }
        void Handle(TcpClient client) {
            client.ReceiveTimeout = 4000; client.SendTimeout = 4000;
            using (var stream = client.GetStream()) {
                var secret = key();
                string challenge = RandomHex(32);
                WriteLine(stream, "WMP1 " + challenge);
                var parts = ReadLine(stream, 512).Split(' ');
                if (parts.Length != 3 || !IsHex(parts[1], 64) || !IsHex(parts[2], 64)) return;
                string command = parts[0], nonce = parts[1];
                if (command != "status" && command != "sleep" && command != "shutdown" && command != "cancel") return;
                string request = "request\n" + challenge + "\n" + nonce + "\n" + command;
                if (!Equal(parts[2], Mac(secret, request))) { Thread.Sleep(150); return; }
                // Rotation invalidates even already-issued challenges.
                if (!Equal(Hex(secret), Hex(key()))) return;
                string result = execute(command);
                WriteLine(stream, result + " " + Mac(secret, "response\n" + challenge + "\n" + nonce + "\n" + command + "\n" + result));
            }
        }
        public static string ReadLine(Stream stream, int max) {
            var bytes = new MemoryStream();
            for (int i = 0; i <= max; i++) {
                int b = stream.ReadByte();
                if (b < 0) throw new IOException("Connection closed");
                if (b == 10) return Encoding.ASCII.GetString(bytes.ToArray());
                if (b < 32 || b > 126) throw new IOException("Invalid protocol");
                bytes.WriteByte((byte)b);
            }
            throw new IOException("Frame too large");
        }
        public static void WriteLine(Stream stream, string line) { var data = Encoding.ASCII.GetBytes(line + "\n"); stream.Write(data, 0, data.Length); stream.Flush(); }
        public static string RandomHex(int count) { var bytes = new byte[count]; using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes); return Hex(bytes); }
        public static string Hex(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant(); }
        public static byte[] Unhex(string text) { var bytes = new byte[text.Length / 2]; for (int i = 0; i < bytes.Length; i++) bytes[i] = Convert.ToByte(text.Substring(i * 2, 2), 16); return bytes; }
        public static bool IsHex(string text, int length) { if (text.Length != length) return false; foreach (char c in text) if (!(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f')) return false; return true; }
        public static string Mac(byte[] secret, string text) { using (var h = new HMACSHA256(secret)) return Hex(h.ComputeHash(Encoding.UTF8.GetBytes(text))); }
        public static bool Equal(string a, string b) { if (a.Length != b.Length) return false; int diff = 0; for (int i = 0; i < a.Length; i++) diff |= a[i] ^ b[i]; return diff == 0; }
        public void Dispose() { stopped = true; listener.Stop(); }
    }
}
