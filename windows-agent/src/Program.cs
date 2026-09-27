using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WakeMyPc {
    static class Program {
        [STAThread] static void Main(string[] args) {
            if (args.Length == 4 && args[0] == "--test-server") {
                // This isolated mode can never call a power API, persist a key,
                // enable startup, or bind anything except loopback.
                var secret = AgentServer.Unhex(args[2]);
                using (var server = new AgentServer(IPAddress.Loopback, int.Parse(args[1]), () => secret, command => command == "status" ? "online" : "simulated")) {
                    server.Start(); File.WriteAllText(args[3], server.Port.ToString());
                    Thread.Sleep(120000);
                }
                return;
            }
            bool first;
            using (var mutex = new Mutex(true, "Local\\WakeMyPcAgent", out first)) {
                if (!first) { if (!args.Contains("--background")) MessageBox.Show("Wake My PC Agent đang chạy. Mở biểu tượng ở khay hệ thống."); return; }
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                try { Application.Run(new AgentForm(args.Contains("--background"))); }
                catch (Exception e) { MessageBox.Show("Không thể mở Agent: " + e.Message, "Wake My PC"); }
            }
        }
    }
    sealed class AgentForm : Form {
        readonly NotifyIcon tray;
        readonly TextBox pairing, details;
        readonly Label status;
        readonly System.Windows.Forms.Timer timer;
        readonly AgentServer server;
        byte[] secret;
        string pending;
        DateTime deadline;
        bool exiting;
        readonly string secretPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WakeMyPcAgent", "pairing.bin");
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        public AgentForm(bool background) {
            Text = "Wake My PC · Windows Agent"; ClientSize = new Size(570, 610); MinimumSize = new Size(550, 630);
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            Font = new Font("Segoe UI", 10); BackColor = Color.FromArgb(242,245,250); StartPosition = FormStartPosition.CenterScreen;
            Directory.CreateDirectory(Path.GetDirectoryName(secretPath));
            secret = File.Exists(secretPath) ? ProtectedData.Unprotect(File.ReadAllBytes(secretPath), null, DataProtectionScope.CurrentUser) : NewSecret();
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 10 };
            Controls.Add(layout);
            layout.Controls.Add(new Label { Text = "Điều khiển PC từ điện thoại", AutoSize = true, Font = new Font("Segoe UI", 20, FontStyle.Bold), ForeColor = Color.FromArgb(16,27,45), Margin = new Padding(0,0,0,14) });
            status = new Label { Text = "Đang khởi động…", AutoSize = true, ForeColor = Color.FromArgb(37,99,235), Margin = new Padding(0,0,0,12) }; layout.Controls.Add(status);
            details = new TextBox { Multiline = true, ReadOnly = true, Height = 108, Dock = DockStyle.Top, ScrollBars = ScrollBars.Vertical, BackColor = Color.White };
            details.Text = NetworkDetails(); layout.Controls.Add(details);
            layout.Controls.Add(new Label { Text = "Trong app → menu của PC → Ghép nối Windows Agent.\nNhập IP của PC và mã bên dưới. Giữ mã này riêng tư.", AutoSize = true, Margin = new Padding(0,14,0,8) });
            pairing = new TextBox { ReadOnly = true, Dock = DockStyle.Top, Font = new Font("Consolas", 11), Text = AgentServer.Hex(secret), UseSystemPasswordChar = true }; layout.Controls.Add(pairing);
            var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top };
            var qrButton = new Button { Text = "Hiện QR ghép nối", AutoSize = true };
            qrButton.Click += (s,e) => { using (var qr = new PairingQrForm(secret)) qr.ShowDialog(this); };
            buttons.Controls.Add(qrButton);
            var show = new CheckBox { Text = "Hiện mã", AutoSize = true }; show.CheckedChanged += (s,e) => pairing.UseSystemPasswordChar = !show.Checked; buttons.Controls.Add(show);
            var copy = new Button { Text = "Sao chép", AutoSize = true }; copy.Click += (s,e) => Clipboard.SetText(pairing.Text); buttons.Controls.Add(copy);
            var rotate = new Button { Text = "Đổi mã", AutoSize = true }; rotate.Click += (s,e) => { if (MessageBox.Show("Hủy ghép nối tất cả điện thoại cũ?", Text, MessageBoxButtons.YesNo) == DialogResult.Yes) { pending = null; secret = NewSecret(); pairing.Text = AgentServer.Hex(secret); status.Text = "Đã đổi mã. Ghép nối lại điện thoại."; } }; buttons.Controls.Add(rotate); layout.Controls.Add(buttons);
            var startup = new CheckBox { Text = "Chạy nền khi đăng nhập Windows", AutoSize = true, Margin = new Padding(0,16,0,12) };
            using (var key = Registry.CurrentUser.OpenSubKey(RunKey)) startup.Checked = key != null && key.GetValue("WakeMyPcAgent") != null;
            startup.CheckedChanged += (s,e) => { try { using (var key = Registry.CurrentUser.CreateSubKey(RunKey)) { if (startup.Checked) key.SetValue("WakeMyPcAgent", "\"" + Application.ExecutablePath + "\" --background"); else key.DeleteValue("WakeMyPcAgent", false); } } catch (Exception ex) { MessageBox.Show(ex.Message); } }; layout.Controls.Add(startup);
            var cancel = new Button { Text = "Hủy lệnh đang chờ", Height = 40, Dock = DockStyle.Top }; cancel.Click += (s,e) => Cancel(); layout.Controls.Add(cancel);
            layout.Controls.Add(new Label { Text = "Đóng cửa sổ để tiếp tục chạy ở khay hệ thống.\nCho phép TCP 47991 trên mạng Private (chạy Enable-Firewall.ps1).\nLệnh Sleep/Tắt máy chờ 10 giây để bạn có thể hủy.\nTắt máy không ép đóng ứng dụng chưa lưu.", AutoSize = true, ForeColor = Color.FromArgb(99,117,139), Margin = new Padding(0,16,0,0) });
            tray = new NotifyIcon { Icon = Icon, Text = "Wake My PC Agent", Visible = true };
            var menu = new ContextMenuStrip(); menu.Items.Add("Mở / Ghép nối", null, (s,e) => Open()); menu.Items.Add("Hủy lệnh đang chờ", null, (s,e) => Cancel()); menu.Items.Add("Thoát Agent", null, (s,e) => { exiting = true; Close(); }); tray.ContextMenuStrip = menu; tray.DoubleClick += (s,e) => Open();
            server = new AgentServer(IPAddress.Any, 47991, () => secret, command => (string)Invoke(new Func<string>(() => HandleCommand(command))));
            timer = new System.Windows.Forms.Timer { Interval = 250 }; timer.Tick += Tick;
            Shown += (s,e) => { try { server.Start(); status.Text = "Sẵn sàng · TCP 47991"; timer.Start(); if (background) Hide(); } catch (Exception ex) { status.Text = "Không mở được cổng: " + ex.Message; } };
            FormClosing += (s,e) => { if (!exiting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } else { timer.Stop(); server.Dispose(); tray.Visible = false; tray.Dispose(); } };
        }
        byte[] NewSecret() { var bytes = AgentServer.Unhex(AgentServer.RandomHex(16)); File.WriteAllBytes(secretPath, ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser)); return bytes; }
        void Open() { Show(); WindowState = FormWindowState.Normal; Activate(); details.Text = NetworkDetails(); }
        void Cancel() { pending = null; status.Text = "Đã hủy lệnh đang chờ · Sẵn sàng"; }
        string HandleCommand(string command) {
            if (command == "status") return "online";
            if (command == "cancel") { Cancel(); return "cancelled"; }
            if (pending != null) return "busy";
            pending = command; deadline = DateTime.UtcNow.AddSeconds(10);
            tray.ShowBalloonTip(8000, "Wake My PC", (command == "sleep" ? "Sleep" : "Tắt máy") + " sau 10 giây. Mở Agent để hủy.", ToolTipIcon.Info);
            return "accepted";
        }
        void Tick(object sender, EventArgs args) {
            if (pending == null) return;
            status.Text = (pending == "sleep" ? "Sleep" : "Tắt máy") + " sau " + Math.Max(0, (int)Math.Ceiling((deadline - DateTime.UtcNow).TotalSeconds)) + " giây — bấm Hủy nếu cần.";
            if (DateTime.UtcNow < deadline) return;
            string command = pending; pending = null;
            try { Power.Execute(command); status.Text = "Đã yêu cầu Windows thực hiện " + command; }
            catch (Exception ex) { status.Text = "Windows chưa thực hiện: " + ex.Message; tray.ShowBalloonTip(5000, "Lệnh không hoàn tất", status.Text, ToolTipIcon.Warning); }
        }
        static string NetworkDetails() {
            var result = new StringBuilder("Máy: " + Environment.MachineName + "\r\n");
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)) {
                foreach (var address in nic.GetIPProperties().UnicastAddresses.Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork)) result.AppendLine("IP: " + address.Address + "   MAC: " + BitConverter.ToString(nic.GetPhysicalAddress().GetAddressBytes()));
            }
            return result.ToString();
        }
    }
    static class Power {
        [StructLayout(LayoutKind.Sequential)] struct Luid { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)] struct Privileges { public uint Count; public Luid Luid; public uint Attributes; }
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disable, ref Privileges state, uint length, IntPtr previous, IntPtr returned);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("powrprof.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.U1)] static extern bool SetSuspendState([MarshalAs(UnmanagedType.U1)] bool hibernate, [MarshalAs(UnmanagedType.U1)] bool force, [MarshalAs(UnmanagedType.U1)] bool disableWake);
        public static void Execute(string command) {
            if (command == "shutdown") {
                Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "shutdown.exe"), "/s /t 0") { UseShellExecute = false, CreateNoWindow = true });
            } else if (command == "sleep") {
                IntPtr token;
                if (!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x28, out token)) throw new Win32Exception();
                try {
                    var state = new Privileges { Count = 1, Attributes = 2 };
                    if (!LookupPrivilegeValue(null, "SeShutdownPrivilege", out state.Luid) || !AdjustTokenPrivileges(token, false, ref state, 0, IntPtr.Zero, IntPtr.Zero) || Marshal.GetLastWin32Error() != 0) throw new Win32Exception();
                    if (!SetSuspendState(false, false, false)) throw new Win32Exception();
                } finally { CloseHandle(token); }
            } else throw new InvalidOperationException("Unsupported command");
        }
    }
}


