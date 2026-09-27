using System;
using System.Drawing;
using System.Linq;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Windows.Forms;
using QRCoder;

namespace WakeMyPc {
    sealed class PairingQrForm : Form {
        sealed class Endpoint {
            public string Ip, Mac, Name;
            public override string ToString() { return Name + " · " + Ip + " · " + Mac; }
        }
        readonly PictureBox picture;
        readonly ComboBox networks;
        readonly Timer expiry;
        public PairingQrForm(byte[] secret) {
            Text = "Ghép nối bằng QR";
            ClientSize = new Size(520, 555);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 10);
            BackColor = Color.FromArgb(242, 245, 250);
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(20), ColumnCount = 1, RowCount = 4 };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 72));
            Controls.Add(layout);
            layout.Controls.Add(new Label { Text = "Trong app → Ghép nối Windows Agent → Quét QR.\nChọn card mạng có MAC trùng PC đã lưu trong app.", AutoSize = true });
            networks = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList };
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)) {
                var mac = nic.GetPhysicalAddress().GetAddressBytes();
                if (mac.Length != 6 || (mac[0] & 1) != 0 || mac.All(b => b == 0)) continue;
                foreach (var addr in nic.GetIPProperties().UnicastAddresses.Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork))
                    networks.Items.Add(new Endpoint { Ip = addr.Address.ToString(), Mac = BitConverter.ToString(mac).Replace('-', ':'), Name = nic.Name });
            }
            layout.Controls.Add(networks);
            picture = new PictureBox { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.CenterImage, BackColor = Color.White };
            layout.Controls.Add(picture);
            layout.Controls.Add(new Label { AutoSize = true, Text = "QR chứa mã điều khiển máy. Không chia sẻ ảnh QR.\nCửa sổ tự đóng sau 2 phút; mã chỉ bị thu hồi khi Đổi mã.\nNếu không có card mạng, hãy kết nối Wi-Fi / Ethernet." });
            networks.SelectedIndexChanged += (s, e) => {
                var endpoint = (Endpoint)networks.SelectedItem;
                string payload = "wakemypc://pair?v=1&ip=" + Uri.EscapeDataString(endpoint.Ip) + "&mac=" + Uri.EscapeDataString(endpoint.Mac) + "&key=" + AgentServer.Hex(secret);
                using (var generator = new QRCodeGenerator())
                using (var data = generator.CreateQrCode(payload, QRCodeGenerator.ECCLevel.M))
                using (var qr = new QRCode(data)) {
                    var old = picture.Image;
                    picture.Image = qr.GetGraphic(5);
                    if (old != null) old.Dispose();
                }
            };
            if (networks.Items.Count > 0) networks.SelectedIndex = 0;
            expiry = new Timer { Interval = 120000 };
            expiry.Tick += (s, e) => Close();
            expiry.Start();
        }
        protected override void Dispose(bool disposing) {
            if (disposing) {
                if (expiry != null) expiry.Dispose();
                if (picture != null && picture.Image != null) { picture.Image.Dispose(); picture.Image = null; }
            }
            base.Dispose(disposing);
        }
    }
}
