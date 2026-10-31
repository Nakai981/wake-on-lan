import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Power, Monitor, Plus, Sun, Moon, House, List, CircleHelp, Star, Settings2, ArrowLeft, X, Wifi, RefreshCw, Check, MousePointer2, Keyboard, SlidersHorizontal, ScanLine, Clock3, Trash2, Pencil, Link2, ChevronRight, Zap, Circle, Download } from 'lucide-react';
import { useRegisterSW } from 'virtual:pwa-register/react';
import { api, agentRequest, commandPc, saveCode, forgetCode } from './api.mjs';
import { lanInfo, validatePc, parsePairQr, normalizeCode, scanLan, textCommand, keyCommand, quickCommands } from './core.mjs';
import { MouseTransport } from './mouse.mjs';
import './style.css';
import { QrCode, Camera } from 'lucide-react';
import { COMMAND_WAIT_MS, startupWaitMs, scheduleStateCheck, validPowerAuthorization, wakeObservationPhase } from './flow-policy.mjs';

function AgentQrReader({ onDetected }) {
  const [scanning, setScanning] = useState(false), [error, setError] = useState(''), [raw, setRaw] = useState('');
  const video = useRef(), callback = useRef(onDetected);
  callback.current = onDetected;
  const accept = value => {
    try { const qr = parsePairQr(value); callback.current(qr); setScanning(false); setRaw(''); setError(''); }
    catch (e) { setError(e.message); }
  };
  const acceptRef = useRef(accept); acceptRef.current = accept;
  useEffect(() => {
    if (!scanning) return;
    let cancelled = false, controls, detected = false;
    (async () => {
      try {
        const { BrowserQRCodeReader } = await import('@zxing/browser');
        if (cancelled) return;
        controls = await new BrowserQRCodeReader().decodeFromConstraints(
          { audio: false, video: { facingMode: { ideal: 'environment' } } }, video.current,
          result => {
            if (!result || cancelled || detected) return;
            try { parsePairQr(result.getText()); detected = true; acceptRef.current(result.getText()); }
            catch (e) { setError(e.message); }
          });
        if (cancelled) controls.stop();
      } catch { if (!cancelled) { setError('Không mở được camera. Hãy dùng HTTPS hoặc localhost và cấp quyền Camera. Bạn cũng có thể dán nội dung QR bên dưới.'); setScanning(false); } }
    })();
    return () => { cancelled = true; controls?.stop(); };
  }, [scanning]);
  return <div className="agent-qr-reader"><div className="qr-guide-icon"><QrCode size={38} /></div><h3>Thêm PC bằng Windows Agent</h3><p className="setup-hint">Trên PC, mở Windows Agent → Hiện QR ghép nối, chọn card Ethernet rồi đưa mã QR vào camera.</p>
    <Button type="button" className="primary" icon={scanning ? X : Camera} onClick={() => { setError(''); setScanning(v => !v); }}>{scanning ? 'Dừng camera' : 'Mở camera quét QR'}</Button>
    {scanning && <video ref={video} className="qr-video" muted playsInline />}
    <details className="qr-paste"><summary>Dán nội dung QR</summary><Field label="Nội dung mã QR Windows Agent" type="password" autoComplete="off" value={raw} onChange={e => setRaw(e.target.value)} placeholder="wakemypc://pair?..." /><Button type="button" disabled={!raw.trim()} onClick={() => accept(raw.trim())}>Dùng mã QR</Button></details>
    {error && <p className="error" role="alert">{error}</p>}</div>;
}

const blank = { name: '', mac: '', ip: '', broadcast: '', port: 9, retries: 3, timeout: 60, startupDelay: 20, favorite: false, agentPaired: false };
const read = (key, fallback) => { try { return JSON.parse(localStorage.getItem('wmp.' + key)) ?? fallback; } catch { return fallback; } };
function useLocal(key, initial) {
  const [value, setValue] = useState(() => read(key, initial));
  const change = next => setValue(old => {
    const result = typeof next === 'function' ? next(old) : next;
    localStorage.setItem('wmp.' + key, JSON.stringify(result)); return result;
  });
  return [value, change];
}
function Button({ children, icon: Icon, className = '', ...props }) { return <button className={'button ' + className} {...props}>{Icon && <Icon size={18} />}{children}</button>; }
function Modal({ title, close, children, wide }) {
  const ref = useRef();
  useEffect(() => {
    const previous = document.activeElement, oldOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden'; ref.current?.showModal();
    return () => { document.body.style.overflow = oldOverflow; previous?.focus?.(); };
  }, []);
  return <dialog ref={ref} className={'modal ' + (wide ? 'wide' : '')} onCancel={event => { event.preventDefault(); close(); }}>
    <header><h2>{title}</h2><button className="icon" aria-label="Đóng" onClick={close}><X /></button></header>{children}</dialog>;
}
function Field({ label, ...props }) { return <label className="field"><span>{label}</span><input {...props} /></label>; }
function Help({ pc, lan }) {
  return <div className="help">
    <div className="eyebrow">MỘT CHÚT CHUẨN BỊ, KẾT NỐI MỖI NGÀY</div><h1>Luôn sẵn sàng.<br />Dù bạn ở góc nào trong nhà.</h1>
    <p className="muted">Thiết lập một lần để bật và điều khiển máy tính ngay trên điện thoại.</p>
    {pc && <div className="panel"><h3>Kiểm tra {pc.name}</h3>{[
      [!!lan, 'LAN bridge', lan ? `${lan.ip} · ${lan.mask}` : 'Chưa kết nối bridge'],
      [!!pc.ip && !!lan?.contains(pc.ip), 'Cùng subnet', pc.ip || 'Chưa lưu IP'],
      [true, 'MAC Ethernet', pc.mac], [!!(pc.broadcast || lan?.broadcast), 'Địa chỉ gửi', pc.broadcast || lan?.broadcast || 'Chưa xác định'],
      [false, 'BIOS và Windows', 'Cần xác nhận trực tiếp trên PC']
    ].map(([ok, label, detail]) => <div className="diagnostic" key={label}>{ok ? <Check size={18} /> : <CircleHelp size={18} />}<div><b>{label}</b><small>{detail}</small></div></div>)}</div>}
    {[
      ['01', 'Chuẩn bị BIOS / UEFI', 'Bật Wake on LAN, Power On by PCI-E hoặc Resume by LAN. Kiểm tra ErP / Deep Sleep có ngắt nguồn card mạng không. PC cần còn cắm điện; ưu tiên Ethernet.'],
      ['02', 'Thiết lập Windows', 'Device Manager → Network adapters → card Ethernet → Properties. Bật Wake on Magic Packet. Trong Power Management, cho phép thiết bị đánh thức máy và chỉ đánh thức bằng Magic Packet. Thử từ Sleep trước; khả năng Wake từ tắt hoàn toàn phụ thuộc phần cứng và driver.'],
      ['03', 'Tìm IP và MAC', 'Mở Command Prompt trên PC, nhập ipconfig /all. Physical Address của card Ethernet là MAC. IPv4 Address là IP. Nên đặt DHCP reservation để IP ổn định. Không suy đoán MAC từ IP.'],
      ['04', 'PC chưa phản hồi?', 'Kiểm tra cùng LAN, nguồn PC, dây Ethernet, BIOS và firewall. Trạng thái dùng TCP 445, 3389, 22, 80; PC chặn các cổng này có thể vẫn đang bật. Không phản hồi không có nghĩa chắc chắn đã tắt.'],
      ['05', 'Ghép nối Windows Agent', 'Chạy WakeMyPcAgent.exe trên PC, cho phép firewall Private TCP 47991 và ghép mã 32 ký tự hoặc QR. Sleep/Shutdown chờ 10 giây và có thể hủy. Bản EXE phải hỗ trợ các lệnh chuột/phím mới nhất.'],
      ['06', 'PWA và LAN bridge', 'Bridge cần chạy trên NAS, router hoặc máy khác luôn bật cùng LAN. Dữ liệu được lưu trong trình duyệt. Dùng HTTPS để cài PWA và quét QR. Không hỗ trợ Wake qua Internet/4G. Điều khiển cần desktop đã đăng nhập; không điều khiển UAC hoặc màn hình đăng nhập.']
    ].map(([n, title, text]) => <details key={n} className="guide"><summary><span>{n}</span>{title}<ChevronRight size={17} /></summary><p>{text}</p></details>)}
  </div>;
}

function Setup({ existing, lan, reloadNetwork, save, close }) {
  const [mode, setMode] = useState(existing ? 'manual' : 'scan');
  const [form, setForm] = useState(existing || blank), [error, setError] = useState('');
  const [scan, setScan] = useState({ busy: false, done: 0, total: 0, found: [] });
  const [info, setInfo] = useState({ busy: false, message: '' });
  const [agentQr, setAgentQr] = useState(null), [pairing, setPairing] = useState(false);
  const controller = useRef(), nameInput = useRef(), infoController = useRef(), autoValues = useRef({});
  useEffect(() => () => { controller.current?.abort(); infoController.current?.abort(); }, []);
  const update = (key, value) => {
    if (key === 'ip' || key === 'mac') setAgentQr(null);
    if (key === 'ip') {
      infoController.current?.abort(); setInfo({ busy: false, message: '' });
      setForm(p => ({ ...p, ip: value,
        name: p.name === autoValues.current.name ? '' : p.name,
        mac: p.mac === autoValues.current.mac ? '' : p.mac }));
    } else setForm(p => ({ ...p, [key]: value }));
  };
  const loadInfo = async ip => {
    if (!ip) return;
    infoController.current?.abort(); const request = new AbortController(); infoController.current = request;
    setInfo({ busy: true, message: 'Đang lấy tên máy và MAC…' });
    try {
      const result = await api('device-info', { ip }, request.signal);
      if (request.signal.aborted) return;
      setForm(p => {
        if (p.ip !== ip) return p;
        const name = !p.name || p.name === autoValues.current.name ? result.name || '' : p.name;
        const mac = !p.mac || p.mac === autoValues.current.mac ? result.mac || '' : p.mac;
        autoValues.current = { name: result.name, mac: result.mac };
        return { ...p, name, mac };
      });
      setInfo({ busy: false, message: result.mac
        ? (result.name ? 'Đã lấy tên máy và MAC. Bạn có thể chỉnh sửa.' : 'Đã lấy MAC. Mạng không cung cấp tên máy; hãy nhập tên bạn muốn.')
        : 'Không đọc được MAC từ mạng. Hãy nhập MAC Ethernet thủ công.' });
    } catch (e) { if (!request.signal.aborted) setInfo({ busy: false, message: e.message }); }
  };
  const stopScan = () => { controller.current?.abort(); setScan(p => ({ ...p, busy: false })); };
  const chooseMode = value => { stopScan(); setError(''); setMode(value); };
  const runScan = async () => {
    setError(''); controller.current?.abort(); controller.current = new AbortController();
    const signal = controller.current.signal;
    setScan({ busy: true, done: 0, total: 0, found: [] });
    try {
      const network = await reloadNetwork();
      if (signal.aborted) return;
      await scanLan(network, { signal, probe: async (ip, signal) => (await api('discover', { ip }, signal)).found,
        progress: (done, total, found) => setScan(p => ({ ...p, done, total, found: found ? [...p.found, found] : p.found })) });
    } catch (e) { if (!signal.aborted) setError(e.message); }
    finally { if (!signal.aborted) setScan(p => ({ ...p, busy: false })); }
  };
  const selectIp = ip => { update('ip', ip); setError(''); void loadInfo(ip); };
  const applyAgentQr = qr => {
    infoController.current?.abort();
    setAgentQr(qr); setError('');
    const defaultName = `PC ${qr.ip}`;
    setForm(p => ({ ...p, ip: qr.ip, mac: qr.mac, name: !p.name || p.name === autoValues.current.name ? defaultName : p.name }));
    autoValues.current = { name: defaultName };
    void loadInfo(qr.ip);
  };
  const finish = async event => {
    event.preventDefault();
    if (pairing) return;
    try {
      const pc = { ...validatePc(form), id: existing?.id || crypto.randomUUID(), network: lan?.key || form.network || '' };
      if (agentQr) {
        setPairing(true);
        if (pc.ip !== agentQr.ip || pc.mac !== agentQr.mac) throw Error('Thông tin PC đã thay đổi. Hãy quét lại QR.');
        if (await agentRequest(pc.ip, agentQr.key, 'status') !== 'online') throw Error('Windows Agent chưa sẵn sàng.');
        await saveCode(pc.id, agentQr.key); pc.agentPaired = true;
      }
      save(pc);
      controller.current?.abort(); close();
    } catch (e) { setError(e.message); } finally { setPairing(false); }
  };
  return <Modal title={existing ? 'Chỉnh sửa máy tính' : 'Thêm máy tính'} close={() => { if (!pairing) close(); }}>
    <form onSubmit={finish} noValidate>
      <div className="modal-body setup-body">
        <div className="segmented setup-tabs" role="tablist" aria-label="Cách thêm máy tính">
          <button type="button" id="setup-scan-tab" role="tab" aria-selected={mode === 'scan'} aria-controls="setup-scan-panel" className={mode === 'scan' ? 'active' : ''} onClick={() => chooseMode('scan')}><ScanLine size={17} />Quét LAN</button>
          <button type="button" id="setup-manual-tab" role="tab" aria-selected={mode === 'manual'} aria-controls="setup-manual-panel" className={mode === 'manual' ? 'active' : ''} onClick={() => chooseMode('manual')}><Pencil size={17} />Nhập thủ công</button>
          <button type="button" id="setup-qr-tab" role="tab" aria-selected={mode === 'qr'} aria-controls="setup-qr-panel" className={mode === 'qr' ? 'active' : ''} onClick={() => chooseMode('qr')}><QrCode size={17} />Quét QR Agent</button>
        </div>
        {mode === 'scan' ? <section id="setup-scan-panel" role="tabpanel" aria-labelledby="setup-scan-tab" className="setup-discovery">
          <div className="setup-scan-heading"><div><b>Tìm máy trong mạng của bạn</b><small>{lan ? `${lan.interface || 'LAN'} · ${lan.ip}` : 'Bấm quét để kiểm tra kết nối LAN.'}</small></div><Button type="button" className={scan.busy ? '' : 'primary'} icon={scan.busy ? X : ScanLine} onClick={scan.busy ? stopScan : runScan}>{scan.busy ? 'Dừng' : scan.total ? 'Quét lại' : 'Quét LAN'}</Button></div>
          {scan.busy && <div className="setup-progress" role="status"><progress max={scan.total || 1} value={scan.done} /><small>{scan.total ? `${scan.done}/${scan.total} địa chỉ · tìm thấy ${scan.found.length}` : 'Đang kết nối…'}</small></div>}
          {scan.found.includes(lan?.ip) && <div className="bridge-discovered" role="status"><span className="bridge-discovered-icon"><Monitor size={23} /><Check size={11} /></span><div><b>Đã phát hiện 1 PC trong LAN</b><small>Máy đang chạy bridge · {lan.ip}</small></div></div>}
          <div className="scan-results setup-results">{[...scan.found].sort((a, b) => Number(b === lan?.ip) - Number(a === lan?.ip)).map(ip => <button type="button" key={ip} aria-pressed={form.ip === ip} className={[form.ip === ip ? 'selected' : '', ip === lan?.ip ? 'bridge-result' : ''].filter(Boolean).join(' ')} onClick={() => selectIp(ip)}><Monitor size={19} /><span>{ip}{ip === lan?.ip && <small>PC trong LAN · Máy đang chạy bridge</small>}</span>{form.ip === ip ? <Check size={18} /> : ip === lan?.ip && <span className="bridge-badge">Đã phát hiện</span>}</button>)}</div>
          {!scan.busy && scan.total > 0 && !scan.found.length && <p className="setup-hint">Chưa tìm thấy máy. Bạn có thể quét lại hoặc chọn Nhập thủ công.</p>}
          {!scan.busy && scan.found.length > 0 && <p className="setup-hint">Chọn IP để tự lấy tên máy và MAC nếu mạng cung cấp.</p>}
          {!scan.busy && !scan.total && <p className="setup-hint">Giữ PC đang bật và cùng mạng LAN khi quét.</p>}
        </section> : mode === 'qr' ? <section id="setup-qr-panel" role="tabpanel" aria-labelledby="setup-qr-tab">{agentQr ? <div className="bridge-discovered"><Check size={24} /><div><b>Đã đọc QR Windows Agent</b><small>{agentQr.ip} · {agentQr.mac}</small><small>Bấm Hoàn tất để xác thực và lưu ghép nối.</small><Button type="button" onClick={() => setAgentQr(null)}>Quét mã khác</Button></div></div> : <AgentQrReader onDetected={applyAgentQr} />}</section> : <div id="setup-manual-panel" role="tabpanel" aria-labelledby="setup-manual-tab"><p className="setup-hint">Nhập thông tin máy tính, sau đó bấm Hoàn tất.</p></div>}
        <div className="setup-fields">
          <label className="field"><span>Tên máy tính <span className="required">*</span></span><input ref={nameInput} value={form.name} onChange={e => update('name', e.target.value)} placeholder="PC của tôi" autoComplete="off" maxLength={80} /></label>
          <Field label="Địa chỉ IP" value={form.ip} onChange={e => update('ip', e.target.value.trim())} onBlur={() => void loadInfo(form.ip)} placeholder="192.168.0.100" inputMode="decimal" />
          {form.ip && <Button type="button" icon={RefreshCw} disabled={info.busy} onClick={() => void loadInfo(form.ip)}>{info.busy ? 'Đang lấy thông tin…' : 'Tự lấy tên & MAC'}</Button>}
          {info.message && <p className="setup-hint" role="status">{info.message}</p>}
          <Field label="MAC Ethernet *" value={form.mac} onChange={e => update('mac', e.target.value)} placeholder="A4:BB:6D:12:34:56" autoComplete="off" />
          <p className="setup-hint">MAC tự lấy thuộc card mạng tại IP đã chọn. Nếu đó là Wi-Fi, hãy thay bằng MAC Ethernet dùng để Wake. Trên PC: ipconfig /all → Physical Address.</p>
        </div>
        <details className="setup-advanced"><summary>Cấu hình nâng cao</summary><Field label="Broadcast (để trống để tự nhận)" value={form.broadcast} onChange={e => update('broadcast', e.target.value.trim())} placeholder={lan?.broadcast} /><Field label="Thời gian chờ PC khởi động (10–30 giây)" type="number" min="10" max="30" value={form.startupDelay ?? 20} onChange={e => update('startupDelay', e.target.value)} />{[['port', 'Cổng UDP'], ['retries', 'Số lần gửi (1–10)'], ['timeout', 'Thời gian theo dõi phản hồi (5–300 giây)']].map(([key, label]) => <Field key={key} type="number" label={label} value={form[key]} onChange={e => update(key, e.target.value)} />)}</details>
        {error && <p className="error" role="alert">{error}</p>}
      </div>
      <footer><Button type="button" onClick={close} disabled={pairing}>Hủy</Button><Button type="submit" className="primary" icon={Check} disabled={info.busy || pairing}>{pairing ? 'Đang ghép nối…' : 'Hoàn tất'}</Button></footer>
    </form>
  </Modal>;
}


function Pair({ pc, close, paired, toast }) {
  const [ip, setIp] = useState(pc.ip), [code, setCode] = useState(''), [error, setError] = useState(''), [busy, setBusy] = useState(false), [scanning, setScanning] = useState(false);
  const video = useRef(), controls = useRef();
  const applyQr = raw => { const result = parsePairQr(raw); if (result.mac !== pc.mac) throw Error('MAC trong QR không khớp máy đã chọn.'); setIp(result.ip); setCode(result.key); setScanning(false); controls.current?.stop(); };
  useEffect(() => {
    if (!scanning) return;
    let cancelled = false;
    (async () => {
      try {
        const { BrowserQRCodeReader } = await import('@zxing/browser');
        if (cancelled) return;
        const reader = new BrowserQRCodeReader();
        const handle = await reader.decodeFromVideoDevice(undefined, video.current, result => {
          if (result && !cancelled) { try { applyQr(result.getText()); } catch (e) { setError(e.message); } }
        });
        if (cancelled) handle.stop(); else controls.current = handle;
      } catch { if (!cancelled) { setError('Không mở được camera. Dùng HTTPS, cấp quyền Camera hoặc nhập mã thủ công.'); setScanning(false); } }
    })();
    return () => { cancelled = true; controls.current?.stop(); };
  }, [scanning]);
  return <Modal title={'Ghép nối ' + pc.name} close={close}><div className="modal-body"><p>Mở Windows Agent trên PC để xem mã 32 ký tự hoặc QR. Mã được mã hóa trong trình duyệt này; không gửi mã cho bridge.</p><Field label="Địa chỉ IPv4 của PC" value={ip} onChange={e => setIp(e.target.value)} /><Field label="Mã ghép nối" type="password" autoComplete="off" value={code} onChange={e => { const v = e.target.value; if (v.startsWith('wakemypc:')) { try { applyQr(v); } catch (err) { setError(err.message); } } else setCode(v); }} placeholder="32 ký tự từ Windows Agent" /><Button icon={ScanLine} onClick={() => setScanning(v => !v)}>{scanning ? 'Dừng camera' : 'Quét QR Windows Agent'}</Button>{scanning && <video ref={video} className="qr-video" muted playsInline />}{error && <p className="error" role="alert">{error}</p>}</div><footer><Button className="primary" disabled={busy} onClick={async () => { setBusy(true); setError(''); try { const key = normalizeCode(code); if (await agentRequest(ip, key, 'status') !== 'online') throw Error('Agent chưa sẵn sàng.'); await saveCode(pc.id, key); paired({ ...pc, ip, agentPaired: true }); toast('Đã ghép nối Windows Agent'); close(); } catch (e) { setError(e.message); } finally { setBusy(false); } }}>{busy ? 'Đang xác thực…' : 'Ghép nối'}</Button></footer></Modal>;
}

function Remote({ pc, preview, close, toast }) {
  const [tab, setTab] = useState(0), [speed, setSpeed] = useState(1), [drag, setDrag] = useState(false), [mods, setMods] = useState([]), [text, setText] = useState(''), [sending, setSending] = useState(false), [feedback, setFeedback] = useState('Sẵn sàng');
  const mouse = useRef(), points = useRef(new Map()), start = useRef(), live = !preview && pc?.agentPaired;
  useEffect(() => {
    const transport = new MouseTransport(cmd => live ? commandPc(pc, cmd) : Promise.resolve('input_ok'), () => { setDrag(false); setFeedback('Mất kết nối chuột. Đã yêu cầu nhả nút.'); });
    mouse.current = transport;
    const release = () => { transport.release(); setDrag(false); points.current.clear(); };
    const hidden = () => { if (document.hidden) release(); };
    window.addEventListener('blur', release); document.addEventListener('visibilitychange', hidden);
    return () => { transport.dispose(); window.removeEventListener('blur', release); document.removeEventListener('visibilitychange', hidden); };
  }, [pc?.id, pc?.ip, live]);
  useEffect(() => { mouse.current?.release(); setDrag(false); points.current.clear(); }, [tab]);
  const send = async cmd => {
    if (sending) return; setSending(true);
    try { if (live) { const result = await commandPc(pc, cmd); if (result !== 'input_ok') throw Error('Agent: ' + result); } setFeedback(live ? 'Đã gửi thao tác' : 'Xem trước · thao tác mô phỏng'); }
    catch (e) { toast(e.message); setFeedback(e.message); } finally { setSending(false); }
  };
  const pad = <div className="touchpad" aria-label="Touchpad điều khiển chuột" onContextMenu={e => e.preventDefault()}
    onPointerDown={e => { e.currentTarget.setPointerCapture(e.pointerId); points.current.set(e.pointerId, { x: e.clientX, y: e.clientY }); start.current = { x: e.clientX, y: e.clientY, time: Date.now(), multi: points.current.size > 1 }; }}
    onPointerMove={e => { const old = points.current.get(e.pointerId); if (!old) return; const dx = (e.clientX - old.x) * speed, dy = (e.clientY - old.y) * speed; points.current.set(e.pointerId, { x: e.clientX, y: e.clientY }); if (points.current.size > 1) mouse.current.add('wheel', -dy * 6); else mouse.current.add('move', dx, dy); }}
    onPointerUp={e => { points.current.delete(e.pointerId); const s = start.current; if (s && !s.multi && Date.now() - s.time < 260 && Math.hypot(e.clientX - s.x, e.clientY - s.y) < 8) mouse.current.add('left'); }}
    onPointerCancel={() => { points.current.clear(); mouse.current.release(); setDrag(false); }}
    onWheel={e => { mouse.current.add('wheel', -e.deltaY); }}><div className="pad-dots" /><MousePointer2 size={34} /><b>Chạm để nhấp · Vuốt để di chuyển</b><span>Hai ngón để cuộn</span></div>;
  return <Modal title={preview ? 'Điều khiển · Xem trước' : 'Điều khiển ' + pc.name} close={close} wide><div className="modal-body"><div className="notice">{live ? 'Đang gửi lệnh thật đến Windows Agent. Chọn ô nhập trên PC trước khi gửi văn bản.' : 'Chế độ xem trước · chưa gửi lệnh đến PC.'}</div><div className="segmented">{[[MousePointer2, 'Touchpad'], [SlidersHorizontal, 'Touch Bar'], [Keyboard, 'Bàn phím']].map(([Icon, label], i) => <button className={tab === i ? 'active' : ''} key={label} onClick={() => setTab(i)}><Icon size={17} />{label}</button>)}</div>
      {(tab === 0 || tab === 2) && <>{pad}<div className="mouse-buttons"><Button onClick={() => mouse.current.add('left')}>Nhấp trái</Button><Button className={drag ? 'primary' : ''} onClick={() => { mouse.current.hold(!drag); setDrag(!drag); }}>{drag ? 'Thả kéo' : 'Giữ để kéo'}</Button><Button onClick={() => mouse.current.add('right')}>Nhấp phải</Button></div></>}
      {tab === 0 && <label className="speed">Tốc độ con trỏ <input type="range" min="0.3" max="3" step="0.1" value={speed} onChange={e => setSpeed(+e.target.value)} /><b>{speed.toFixed(1)}×</b></label>}
      {tab === 1 && <><h3>Media & phím tắt</h3><div className="quick-grid">{Object.entries(quickCommands).map(([label, cmd]) => <Button disabled={sending} key={label} onClick={() => void send(cmd)}>{label}</Button>)}</div><h3>Phím chức năng</h3><div className="key-grid">{Array.from({ length: 12 }, (_, i) => 'F' + (i + 1)).map(k => <Button disabled={sending} key={k} onClick={() => void send(keyCommand(k, mods))}>{k}</Button>)}</div></>}
      {tab === 2 && <><label className="field"><span>Văn bản tiếng Việt</span><textarea value={text} onChange={e => setText(e.target.value)} placeholder="Nhập nội dung để gửi đến PC…" /></label><Button className="primary" disabled={sending || !text} onClick={() => { try { void send(textCommand(text)); } catch (e) { toast(e.message); } }}>Gửi văn bản</Button><small>{new TextEncoder().encode(text).length}/240 byte · không tự gửi lại khi lỗi</small><div className="modifiers">{['Ctrl', 'Alt', 'Shift', 'Win'].map(m => <Button className={mods.includes(m) ? 'primary' : ''} key={m} onClick={() => setMods(p => p.includes(m) ? p.filter(v => v !== m) : [...p, m])}>{m}</Button>)}</div><div className="key-grid">{['Esc', 'Tab', 'Enter', 'Backspace', 'Delete', 'Space', '←', '↑', '↓', '→', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'].map(k => <Button key={k} disabled={sending} onClick={() => void send(keyCommand(k, mods))}>{k}</Button>)}</div></>}
      <p className="feedback" role="status">{feedback}</p></div></Modal>;
}

function Countdown({ until }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 250); return () => clearInterval(timer); }, [until]);
  return <span>{Math.max(0, Math.ceil((until - now) / 1000))} giây</span>;
}
function PendingPowerNotice({ pending, cancel }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 250); return () => clearInterval(t); }, []);
  return <div className="pending"><span>Đã gửi {pending.command === 'sleep' ? 'Sleep' : 'Tắt máy'} · Kiểm tra lại sau <Countdown until={pending.until} /></span>{now < pending.cancelUntil && <Button onClick={cancel}>Hủy lệnh</Button>}</div>;
}
function PowerQrGate({ pc, command, close, verified }) {
  const [qr, setQr] = useState(null), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const [method, setMethod] = useState('qr'), [ip, setIp] = useState(pc.ip), [code, setCode] = useState('');
  const submit = async event => {
    event.preventDefault(); if (busy) return;
    setBusy(true); setError('');
    try {
      const target = method === 'qr' ? qr : { ip: ip.trim(), key: normalizeCode(code) };
      if (!target) throw Error('Hãy quét QR Windows Agent trước.');
      if (await agentRequest(target.ip, target.key, 'status') !== 'online') throw Error('Agent chưa sẵn sàng.');
      await saveCode(pc.id, target.key);
      verified({ ...pc, ip: target.ip, agentPaired: true });
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  };
  return <Modal title={'Xác thực Agent trước khi ' + (command === 'sleep' ? 'Sleep' : 'tắt máy')} close={() => { if (!busy) close(); }}><form onSubmit={submit}><div className="modal-body"><p>Xác thực Windows Agent của <b>{pc.name}</b> bằng QR hoặc mã ghép nối trước khi gửi lệnh.</p>
    <div className="segmented" role="tablist" aria-label="Cách xác thực Windows Agent"><button type="button" role="tab" aria-selected={method === 'qr'} className={method === 'qr' ? 'active' : ''} disabled={busy} onClick={() => { setMethod('qr'); setError(''); }}><QrCode size={17} />Quét QR Agent</button><button type="button" role="tab" aria-selected={method === 'manual'} className={method === 'manual' ? 'active' : ''} disabled={busy} onClick={() => { setMethod('manual'); setError(''); }}><Keyboard size={17} />Nhập mã thủ công</button></div>
    {method === 'qr' ? (!qr ? <AgentQrReader onDetected={value => { if (value.mac !== pc.mac) { setError('QR không thuộc MAC của máy đã chọn. Hãy quét đúng Windows Agent.'); return; } setQr(value); setError(''); }} /> : <div className="notice">Đã đọc QR của {pc.name} · {qr.ip}.<br /><Button type="button" disabled={busy} onClick={() => setQr(null)}>Quét lại</Button></div>) : <><Field label="Địa chỉ IPv4 của PC" value={ip} disabled={busy} onChange={e => setIp(e.target.value)} inputMode="decimal" placeholder="192.168.0.100" /><Field label="Mã ghép nối Windows Agent (32 ký tự)" value={code} disabled={busy} type="password" autoComplete="off" onChange={e => setCode(e.target.value)} placeholder="Nhập mã hiển thị trên Windows Agent" /><p className="setup-hint">Mở Windows Agent trên PC để xem mã. App sẽ xác thực mã với PC trước khi cho phép Sleep/Tắt máy.</p></>}
    {error && <p className="error" role="alert">{error}</p>}</div><footer className="agent-auth-footer"><Button type="button" onClick={close} disabled={busy}>Hủy</Button><Button type="submit" disabled={busy || (method === 'qr' ? !qr : !code.trim() || !ip.trim())} className="primary">{busy ? 'Đang xác thực…' : 'Xác thực và tiếp tục'}</Button></footer></form></Modal>;
}
function WakeConsoleOutput({ data }) {
  const output = useRef();
  useEffect(() => { if (output.current) output.current.scrollTop = output.current.scrollHeight; }, [data?.lines.length]);
  const labels = { sending: 'Đang gửi lệnh tới bridge…', booting: 'Đã gửi tín hiệu · Chờ PC khởi động', checking: 'Đang chờ phản hồi từ PC…', online: 'PC đang phản hồi', unknown: 'Chưa nhận phản hồi từ PC', error: 'Không xác nhận được gửi thành công', manual: 'PC đã bật · Xác nhận thủ công' };
  return <div className="modal-body"><p className="wake-console-status" role="status">{labels[data.phase] || 'Theo dõi Wake-on-LAN'}{data.phase === 'booting' && data.readyAt && <> · Chờ <Countdown until={data.readyAt} /></>}</p><div className="wake-console" ref={output} role="log" aria-label="Nhật ký gửi Wake-on-LAN" aria-live="polite">{data.lines.map((line, i) => <div key={i} className={'console-' + line.level}><time>{new Date(line.at).toLocaleTimeString('vi-VN', { hour12: false })}</time><span>{line.text}</span></div>)}</div>{data.packetHex && <details className="wake-packet"><summary>Gói UDP thực tế · 102 byte · HEX</summary><pre>{data.packetHex.match(/.{1,32}/g).map(row => row.match(/../g).join(' ')).join('\n')}</pre></details>}</div>;
}

function App() {
  const [pcs, setPcs] = useLocal('devices', []), [history, setHistory] = useLocal('history', []), [dark, setDark] = useLocal('dark', false);
  const [tab, setTab] = useState('home'), [lan, setLan] = useState(null), [bridgeOnline, setBridgeOnline] = useState(false), [online, setOnline] = useState({}), [manual, setManual] = useState(() => Object.fromEntries(pcs.map(pc => [pc.id, false]))), [busy, setBusy] = useState({}), [modal, setModal] = useState(null), [toastText, setToast] = useState(''), [filter, setFilter] = useState(false), [pendingPower, setPendingPower] = useState(null), [installEvent, setInstallEvent] = useState(null);
  const timer = useRef(), wakeTimers = useRef(new Map()), state = useRef(), refreshing = useRef(false), mounted = useRef(true);
  const [wakeConsole, setWakeConsole] = useState(null);
  const [helpPc, setHelpPc] = useState(null);
  const [manualPinned, setManualPinned] = useState(() => Object.fromEntries(pcs.map(pc => [pc.id, true])));
  const [wakeReadyAt, setWakeReadyAt] = useState({});
  const powerAuthorization = useRef(null), wakeRuns = useRef(new Map());
  const consoleLine = (pc, text, level = 'info', at = new Date().toISOString()) => setWakeConsole(p => p?.pc.id === pc.id ? { ...p, lines: [...p.lines, { text, level, at }] } : p);
  const consolePhase = (pc, phase) => setWakeConsole(p => p?.pc.id === pc.id ? { ...p, phase } : p);
  state.current = { pcs, manual, busy, modal, manualPinned }; const selected = pcs.find(p => p.favorite);
  const { needRefresh: [needRefresh], updateServiceWorker } = useRegisterSW();
  const toast = text => { clearTimeout(timer.current); setToast(text); timer.current = setTimeout(() => setToast(''), 6000); };
  const log = text => setHistory(p => [{ at: new Date().toISOString(), text }, ...p].slice(0, 60));
  const save = pc => {
    if (!state.current.pcs.some(v => v.id === pc.id)) {
      setManual(p => ({ ...p, [pc.id]: false }));
      setManualPinned(p => ({ ...p, [pc.id]: true }));
    }
    setPcs(p => p.some(v => v.id === pc.id) ? p.map(v => v.id === pc.id ? pc : v) : [...p, pc]);
    log('Đã lưu ' + pc.name);
  };
  const reloadNetwork = async () => {
    try { const current = lanInfo(await api('network')); if (mounted.current) { setLan(current); setBridgeOnline(true); } return current; }
    catch (e) { if (mounted.current) { setBridgeOnline(false); setLan(null); } throw e; }
  };
  const checkPc = async pc => pc.ip ? pc.agentPaired ? await commandPc(pc, 'status') === 'online' : (await api('reachable', { ip: pc.ip })).reachable : false;
  const refresh = async () => {
    if (refreshing.current || document.hidden) return; refreshing.current = true;
    try {
      const network = await reloadNetwork();
      const result = await Promise.all(state.current.pcs.map(async pc => { if (state.current.busy[pc.id]) return [pc.id, null]; try { return [pc.id, !!pc.ip && network.contains(pc.ip) && await checkPc(pc)]; } catch { return [pc.id, false]; } }));
      if (!mounted.current) return;
      const usable = result.filter(([id, value]) => typeof value === 'boolean' && !state.current.busy[id]);
      setOnline(p => ({ ...p, ...Object.fromEntries(usable) }));
      setManual(p => { const next = { ...p }; usable.forEach(([id, ok]) => { if (ok && !state.current.manualPinned[id]) delete next[id]; }); return next; });
    } catch { if (mounted.current) setOnline(p => Object.fromEntries(Object.entries(p).filter(([id]) => state.current.busy[id]))); } finally { refreshing.current = false; }
  };
  useEffect(() => { document.documentElement.dataset.theme = dark ? 'dark' : 'light'; }, [dark]);
  useEffect(() => {
    mounted.current = true; void refresh();
    const interval = setInterval(() => void refresh(), 15000), visible = () => { if (!document.hidden) void refresh(); }, install = e => { e.preventDefault(); setInstallEvent(e); };
    document.addEventListener('visibilitychange', visible); window.addEventListener('beforeinstallprompt', install);
    return () => { mounted.current = false; clearInterval(interval); clearTimeout(timer.current); wakeTimers.current.forEach(clearTimeout); document.removeEventListener('visibilitychange', visible); window.removeEventListener('beforeinstallprompt', install); };
  }, []);
  const wakeRaw = async pc => {
    consoleLine(pc, 'Kiểm tra kết nối LAN bridge…');
    const network = await reloadNetwork();
    if (pc.network && pc.network !== network.key) throw Error('Subnet đã thay đổi. Hãy sửa thông tin PC hoặc quét lại trước khi Wake.');
    const target = pc.broadcast || network.broadcast;
    consoleLine(pc, `Bridge: ${network.interface || 'LAN'} · ${network.ip}`);
    consoleLine(pc, `Đích UDP: ${target}:${pc.port} · MAC: ${pc.mac}`);
    consoleLine(pc, `Yêu cầu gửi ${pc.retries} lần · Magic Packet: FF × 6 + MAC × 16 (102 byte)`);
    consoleLine(pc, 'Đang yêu cầu bridge gửi gói UDP…');
    const result = await api('wake', { mac: pc.mac, broadcast: target, port: pc.port, retries: pc.retries });
    if (!result.sent || !Array.isArray(result.attempts) || result.attempts.length !== pc.retries || result.attempts.some(a => a.bytes !== 102)) throw Error('Bridge chưa trả đủ kết quả gửi. Hãy khởi động lại bridge với phiên bản mới; không tự gửi lại lệnh.');
    setWakeConsole(p => p?.pc.id === pc.id ? { ...p, packetHex: result.packetHex } : p);
    result.attempts.forEach(a => consoleLine(pc, `Lần ${a.attempt}/${pc.retries}: socket đã gửi ${a.bytes} byte → ${result.target.address}:${result.target.port}`, 'success', a.sentAt));
    consoleLine(pc, `Nguồn gửi: ${result.source.address}:${result.source.port}`);
    consoleLine(pc, 'Đã gửi tín hiệu Wake-on-LAN. Chuẩn bị chờ PC khởi động.', 'success');
    consoleLine(pc, 'UDP không có xác nhận nhận gói; kết quả gửi chưa xác nhận PC đã bật.');
    consolePhase(pc, 'booting');
    log('Đã gửi Wake: ' + pc.name);
    // Let the browser paint the console receipts before showing the notification.
    await new Promise(resolve => requestAnimationFrame(() => setTimeout(resolve, 0)));
    toast('Đã gửi tín hiệu Wake-on-LAN đến ' + pc.name);
  };
  const wake = async pc => {
    if (state.current.busy[pc.id]) return;
    setWakeConsole({ pc, phase: 'sending', lines: [], packetHex: '' });
    setModal({ type: 'wakeConsole', pc });
    setBusy(p => ({ ...p, [pc.id]: 'wake' }));
    setWakeReadyAt(p => ({ ...p, [pc.id]: null }));
    const run = {}; wakeRuns.current.set(pc.id, run);
    try {
      await wakeRaw(pc);
      if (wakeRuns.current.get(pc.id) !== run) return;
      setPcs(p => p.map(v => v.id === pc.id ? { ...v, lastWake: new Date().toISOString() } : v));
      const started = Date.now();
      const waitMs = startupWaitMs(pc.startupDelay);
      setWakeReadyAt(p => ({ ...p, [pc.id]: started + waitMs }));
      setWakeConsole(p => p?.pc.id === pc.id ? { ...p, readyAt: started + waitMs } : p);
      consoleLine(pc, `Kiểm tra phản hồi ngay và mỗi 3 giây. PC phản hồi sẽ chuyển sang Đã bật ngay; nếu chưa phản hồi, chờ khởi động ${waitMs / 1000} giây. Có thể bỏ qua để xác nhận thủ công.`);
      const poll = async () => {
        if (wakeRuns.current.get(pc.id) !== run) return;
        if (Date.now() >= started + waitMs) consolePhase(pc, 'checking');
        try {
          const ok = await checkPc(pc);
          if (!mounted.current || wakeRuns.current.get(pc.id) !== run) return;
          const phase = wakeObservationPhase(ok, started + waitMs);
          if (phase !== 'booting') {
            setManualPinned(p => { const next = { ...p }; delete next[pc.id]; return next; });
            setManual(p => { const next = { ...p }; delete next[pc.id]; return next; });
            setOnline(p => ({ ...p, [pc.id]: ok }));
          }
          consoleLine(pc, ok ? 'PC đang phản hồi tại IP đã lưu.' : 'Chưa nhận phản hồi từ PC tại IP đã lưu.', ok ? 'success' : 'info');
          consolePhase(pc, phase);
          if (ok) { setOnline(p => ({ ...p, [pc.id]: true })); setModal(p => p?.type === 'wakeResult' && p.pc.id === pc.id ? null : p); setBusy(p => ({ ...p, [pc.id]: null })); wakeTimers.current.delete(pc.id); toast(pc.name + ' đang phản hồi'); log('PC phản hồi: ' + pc.name); return; }
          if (phase === 'unknown' && !state.current.modal) setModal({ type: 'wakeResult', pc });
          if (Date.now() - started >= waitMs + pc.timeout * 1000) { setBusy(p => ({ ...p, [pc.id]: null })); wakeTimers.current.delete(pc.id); return; }
          wakeTimers.current.set(pc.id, setTimeout(poll, 3000));
        } catch (e) {
          if (mounted.current && wakeRuns.current.get(pc.id) === run) {
            consoleLine(pc, e.message, 'error');
            const phase = wakeObservationPhase(false, started + waitMs); consolePhase(pc, phase);
            if (Date.now() - started < waitMs + pc.timeout * 1000) wakeTimers.current.set(pc.id, setTimeout(poll, 3000));
            else { setBusy(p => ({ ...p, [pc.id]: null })); wakeTimers.current.delete(pc.id); }
            if (phase === 'unknown' && !state.current.modal) setModal({ type: 'wakeResult', pc });
          }
        }
      };
      void poll();
    } catch (e) { consoleLine(pc, e.message, 'error'); consolePhase(pc, 'error'); toast(e.message); setBusy(p => ({ ...p, [pc.id]: null })); }
  };
  const stopWake = pc => { wakeRuns.current.delete(pc.id); clearTimeout(wakeTimers.current.get(pc.id)); wakeTimers.current.delete(pc.id); setBusy(p => ({ ...p, [pc.id]: null })); consoleLine(pc, 'Đã dừng theo dõi. Không gửi thêm gói UDP.'); };
  const pcNotStarted = pc => {
    stopWake(pc);
    setManualPinned(p => ({ ...p, [pc.id]: true }));
    setManual(p => ({ ...p, [pc.id]: false }));
    setHelpPc(pc); setModal(null); setTab('help');
    log('Người dùng xác nhận PC chưa bật: ' + pc.name);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };
  const skipWakeWait = pc => { stopWake(pc); setManualPinned(p => ({ ...p, [pc.id]: true })); setManual(p => ({ ...p, [pc.id]: true })); consoleLine(pc, 'Người dùng bỏ qua thời gian chờ và xác nhận PC đã bật.', 'success'); consolePhase(pc, 'manual'); log('Xác nhận thủ công PC đã bật: ' + pc.name); };
  const changeManualStatus = (pc, value) => {
    setManualPinned(p => ({ ...p, [pc.id]: true }));
    setManual(p => ({ ...p, [pc.id]: value }));
    log(`Trạng thái thủ công: ${pc.name} · ${value ? 'Đã bật' : 'Chưa bật'}`);
  };
  const automaticStatus = pc => {
    setManualPinned(p => { const next = { ...p }; delete next[pc.id]; return next; });
    setManual(p => { const next = { ...p }; delete next[pc.id]; return next; });
    void refresh();
  };
  const power = async (pc, command) => {
    const proof = powerAuthorization.current;
    if (!validPowerAuthorization(proof, pc, command)) {
      powerAuthorization.current = null; setModal({ type: 'powerQr', pc, command }); return;
    }
    powerAuthorization.current = null;
    setBusy(p => ({ ...p, [pc.id]: command })); setModal(null);
    try {
      const result = await commandPc(pc, command);
      if (!['accepted', 'simulated'].includes(result)) throw Error('Agent: ' + result);
      log(`${command === 'sleep' ? 'Sleep' : 'Shutdown'} đã được Agent tiếp nhận: ${pc.name}`);
      setPendingPower({ pc, command, until: Date.now() + COMMAND_WAIT_MS, cancelUntil: Date.now() + 10000 });
      toast('Agent đã nhận lệnh. App chờ 20 giây rồi kiểm tra lại; có thể hủy lệnh trong 10 giây đầu.');
    } catch (e) { toast(e.message); setBusy(p => ({ ...p, [pc.id]: null })); }
  };
  useEffect(() => {
    if (!pendingPower) return;
    let cancelled = false;
    const t = scheduleStateCheck(pendingPower.until - COMMAND_WAIT_MS, async () => {
      let responding = false;
      try { responding = await checkPc(pendingPower.pc); } catch { /* Silence is unknown. */ }
      if (cancelled || !mounted.current) return;
      const id = pendingPower.pc.id;
      setManualPinned(p => { const next = { ...p }; delete next[id]; return next; });
      setManual(p => { const next = { ...p }; delete next[id]; return next; });
      setOnline(p => ({ ...p, [id]: responding }));
      setBusy(p => ({ ...p, [id]: null })); setPendingPower(null);
      toast(responding ? 'PC vẫn đang phản hồi sau 20 giây.' : 'Đã chờ 20 giây. PC chưa phản hồi; chưa xác nhận chắc chắn đã Sleep/tắt.');
    });
    return () => { cancelled = true; clearTimeout(t); };
  }, [pendingPower]);
  const status = pc => busy[pc.id] === 'wake' ? (!wakeReadyAt[pc.id] ? 'Đang gửi tín hiệu' : Date.now() < wakeReadyAt[pc.id] ? 'Đang chờ PC khởi động' : 'Đang chờ phản hồi từ PC') : ['sleep', 'shutdown'].includes(busy[pc.id]) ? 'Đã gửi lệnh · Đang chờ 20 giây' : manualPinned[pc.id] ? `${manual[pc.id] ? 'Đã bật' : 'Chưa bật'} · thủ công` : manual[pc.id] === true ? 'Đã bật · xác nhận thủ công' : manual[pc.id] === false ? 'Chưa xác định' : online[pc.id] ? 'Đang hoạt động' : 'Chưa xác định';
  const isOnline = pc => manual[pc.id] ?? online[pc.id] ?? false;
  const powerDialog = (pc, command) => {
    if (pendingPower) { toast('Hãy chờ lệnh nguồn hiện tại hoàn tất trước.'); return; }
    powerAuthorization.current = null; setModal({ type: 'powerQr', pc, command });
  };
  const heroOnline = selected && isOnline(selected);
  return <div className={'app ' + (tab === 'home' && selected && !heroOnline ? 'sleep-mode' : '')}>
    <header className="topbar"><a className="brand" href="#" onClick={e => { e.preventDefault(); setTab('home'); }}><span className="brand-icon"><Power size={22} /></span>Wake My PC<span className="web-label">WEB</span></a><div className="top-actions"><span className={'network-pill ' + (bridgeOnline ? 'connected' : '')}><span />{bridgeOnline ? 'LAN đã kết nối' : 'Bridge offline'}</span><button className="icon" aria-label={dark ? 'Giao diện sáng' : 'Giao diện tối'} onClick={() => setDark(v => !v)}>{dark ? <Sun size={20} /> : <Moon size={20} />}</button><button className="icon" aria-label="Lịch sử hoạt động" onClick={() => setModal({ type: 'history' })}><Clock3 size={20} /></button></div></header>
    <main>
      {needRefresh && <div className="update-banner">Có phiên bản mới. <Button onClick={() => void updateServiceWorker(true)}>Tải lại ứng dụng</Button></div>}
      {tab === 'home' && <>
        <div className="section-top"><div><div className="eyebrow">KHÔNG GIAN CỦA BẠN</div><h1>Một chạm. Sẵn sàng.</h1><p className="muted">Máy tính luôn trong tầm tay.</p></div><span className="date">{new Intl.DateTimeFormat('vi-VN', { day: '2-digit', month: 'long' }).format(new Date())}</span></div>
        {selected ? <><section className={'hero ' + (heroOnline ? 'awake' : '')}><div className="hero-top"><span className="tag"><span className={'dot ' + (heroOnline ? 'on' : '')} />{status(selected)}</span><button className="icon" aria-label="Chi tiết máy mặc định" onClick={() => setModal({ type: 'detail', pc: selected })}><Settings2 size={20} /></button></div><div className="computer-art"><Monitor strokeWidth={1} size={120} /><span className="art-glow" /></div><h2>{selected.name}</h2><p>{selected.ip || 'Chưa lưu IP'} <span>·</span> {selected.mac}</p>
          {heroOnline ? <div className="power-actions"><Button icon={Moon} disabled={!!busy[selected.id]} onClick={() => powerDialog(selected, 'sleep')}>Sleep</Button><Button icon={Power} disabled={!!busy[selected.id]} onClick={() => powerDialog(selected, 'shutdown')}>Tắt máy</Button></div> : <button className="wake-button" aria-label={'Bật ' + selected.name} disabled={!!busy[selected.id]} onClick={() => void wake(selected)}><Power size={38} /><span>{busy[selected.id] ? 'ĐANG GỬI' : 'BẬT PC'}</span></button>}
          <div className="manual-status"><div className="manual-status-heading"><span>Trạng thái thủ công</span><button type="button" disabled={!!busy[selected.id]} onClick={() => automaticStatus(selected)}>{manualPinned[selected.id] ? 'Về tự động' : 'Đang tự động'}</button></div><div className="manual-status-options" role="group" aria-label="Đổi trạng thái PC thủ công"><button type="button" disabled={!!busy[selected.id]} aria-pressed={!!manualPinned[selected.id] && manual[selected.id] === true} className={manualPinned[selected.id] && manual[selected.id] === true ? 'active' : ''} onClick={() => changeManualStatus(selected, true)}><Check size={15} />Đã bật</button><button type="button" disabled={!!busy[selected.id]} aria-pressed={!!manualPinned[selected.id] && manual[selected.id] === false} className={manualPinned[selected.id] && manual[selected.id] === false ? 'active' : ''} onClick={() => changeManualStatus(selected, false)}><Moon size={15} />Chưa bật</button></div><small>Chỉ đổi hiển thị, không gửi lệnh bật/tắt PC.</small></div>
          <div className="hero-bottom"><span>{manualPinned[selected.id] ? 'Trạng thái do bạn chọn · Giữ trong phiên này' : heroOnline ? 'Kết nối cùng LAN · sẵn sàng điều khiển' : 'Không phản hồi không đồng nghĩa PC đã tắt'}</span>{busy[selected.id] === 'wake' && <button onClick={() => pcNotStarted(selected)}>PC chưa được bật</button>}</div></section>
          {heroOnline && <button className="remote-card" onClick={() => setModal({ type: selected.agentPaired ? 'remote' : 'pair', pc: selected })}><span className="tile"><MousePointer2 size={24} /></span><div><b>Điều khiển máy tính</b><small>Touchpad, bàn phím & media</small></div><ChevronRight /></button>}
          {selected.network && lan && selected.network !== lan.key && <div className="notice warning">Subnet đã thay đổi. Mở chi tiết máy → Chỉnh sửa hoặc quét lại để cập nhật.</div>}
        </> : <section className="empty"><div className="empty-orbit"><Monitor size={62} strokeWidth={1.4} /><span><Star size={19} /></span></div><h2>{pcs.length ? 'Chọn chiếc PC của bạn' : 'Chào mừng về nhà.'}</h2><p>{pcs.length ? 'Đánh dấu một ngôi sao trong Danh sách để đưa máy lên màn hình chính.' : 'Thêm máy tính đầu tiên. Sẵn sàng cho một cách kết nối nhẹ nhàng hơn.'}</p><Button className="primary" icon={pcs.length ? Star : Plus} onClick={() => pcs.length ? setTab('list') : setModal({ type: 'setup' })}>{pcs.length ? 'Chọn máy mặc định' : 'Thêm máy tính'}</Button></section>}
        <div className="home-bottom"><span><Zap size={16} /> Kết nối trong mạng nội bộ của bạn</span><button onClick={() => setModal({ type: 'remote', preview: true })}>Thử giao diện điều khiển <ChevronRight size={14} /></button></div>
      </>}
      {tab === 'list' && <><div className="section-top"><div><div className="eyebrow">THIẾT BỊ CỦA BẠN</div><h1>Danh sách máy tính<span className="count">{pcs.length}</span></h1><p className="muted">Chọn một ngôi sao để đặt máy mặc định.</p></div><Button className="primary" icon={Plus} onClick={() => setModal({ type: 'setup' })}>Thêm máy</Button></div><div className="list-tools"><button className={'filter ' + (filter ? 'active' : '')} onClick={() => setFilter(v => !v)}><Star size={15} />Chỉ máy mặc định</button><Button icon={RefreshCw} onClick={() => void refresh()}>Làm mới</Button></div><div className="devices">{pcs.filter(pc => !filter || pc.favorite).map(pc => <article className="device-card" key={pc.id}><div className="device-row"><span className="device-icon"><Monitor size={27} /></span><div className="device-title"><h3>{pc.name}</h3><small>{pc.ip || 'Chưa lưu IP'}</small></div><button className={'icon favorite ' + (pc.favorite ? 'chosen' : '')} aria-label={pc.favorite ? 'Bỏ máy mặc định' : 'Chọn làm máy mặc định'} onClick={() => setPcs(p => p.map(v => ({ ...v, favorite: v.id === pc.id && !pc.favorite })))}><Star fill={pc.favorite ? 'currentColor' : 'none'} size={21} /></button><button className="icon" aria-label={'Chi tiết ' + pc.name} onClick={() => setModal({ type: 'detail', pc })}><Settings2 size={20} /></button></div><div className="device-meta"><span className={'tag ' + (isOnline(pc) ? 'positive' : '')}><Circle size={7} fill="currentColor" />{status(pc)}</span><small>{pc.mac}</small></div><div className="device-actions"><Button icon={Power} className="primary" disabled={!!busy[pc.id]} onClick={() => void wake(pc)}>Bật PC</Button>{isOnline(pc) && <Button onClick={() => setModal({ type: pc.agentPaired ? 'remote' : 'pair', pc })}>Điều khiển</Button>}{busy[pc.id] === 'wake' && <Button onClick={() => pcNotStarted(pc)}>PC chưa được bật</Button>}</div></article>)}</div>{(!pcs.length || (filter && !pcs.some(p => p.favorite))) && <div className="empty"><Monitor size={52} /><h2>{pcs.length ? 'Chưa chọn máy mặc định' : 'Chưa có máy tính'}</h2><p>{pcs.length ? 'Tắt bộ lọc và chọn ngôi sao bên cạnh một máy.' : 'Bắt đầu bằng cách thêm máy tính trong LAN.'}</p></div>}</>}
      {tab === 'help' && <Help pc={helpPc || selected} lan={lan} />}
    </main>
    <nav className="bottom-nav" aria-label="Điều hướng chính">{[[House, 'home', 'Trang chủ'], [List, 'list', 'Danh sách'], [CircleHelp, 'help', 'Trợ giúp']].map(([Icon, value, label]) => <button key={value} className={tab === value ? 'active' : ''} onClick={() => setTab(value)}><Icon size={21} /><span>{label}</span></button>)}</nav>
    {installEvent && <button className="install" onClick={async () => { await installEvent.prompt(); setInstallEvent(null); }}><Download size={17} />Cài ứng dụng</button>}
    {pendingPower && <PendingPowerNotice pending={pendingPower} cancel={async () => { try { const result = await commandPc(pendingPower.pc, 'cancel'); if (!['cancelled', 'simulated'].includes(result)) throw Error('Agent: ' + result); log('Đã hủy lệnh nguồn: ' + pendingPower.pc.name); setBusy(p => ({ ...p, [pendingPower.pc.id]: null })); setPendingPower(null); toast('Đã hủy lệnh'); void refresh(); } catch (e) { toast(e.message); } }} />}
    {toastText && <div className="toast" role="status">{toastText}<button aria-label="Ẩn thông báo" onClick={() => setToast('')}><X size={16} /></button></div>}
    {modal?.type === 'wakeConsole' && wakeConsole && <Modal title={'Console · ' + wakeConsole.pc.name} close={() => setModal(null)} wide><WakeConsoleOutput data={wakeConsole} /><footer>{['booting', 'checking', 'unknown'].includes(wakeConsole.phase) && <Button className="primary" onClick={() => skipWakeWait(wakeConsole.pc)}>Bỏ qua — PC đã bật</Button>}{(busy[wakeConsole.pc.id] === 'wake' || wakeConsole.phase === 'unknown') && wakeConsole.phase !== 'sending' && <Button onClick={() => pcNotStarted(wakeConsole.pc)}>PC chưa được bật</Button>}<Button onClick={() => setModal(null)}>Đóng console</Button></footer></Modal>}
    {modal?.type !== 'wakeConsole' && wakeConsole?.phase === 'booting' && busy[wakeConsole.pc.id] === 'wake' && <div className="pending"><span>Chờ PC khởi động · <Countdown until={wakeConsole.readyAt || Date.now() + startupWaitMs(wakeConsole.pc.startupDelay)} /></span><Button onClick={() => skipWakeWait(wakeConsole.pc)}>Bỏ qua — PC đã bật</Button></div>}
    {modal?.type === 'powerQr' && <PowerQrGate pc={modal.pc} command={modal.command} close={() => setModal(null)} verified={pc => { const command = modal.command; save(pc); powerAuthorization.current = { id: pc.id, ip: pc.ip, mac: pc.mac, command, at: Date.now() }; setModal({ type: 'power', pc, command }); }} />}

    {modal?.type === 'setup' && <Setup existing={modal.pc} lan={lan} reloadNetwork={reloadNetwork} save={save} close={() => setModal(null)} toast={toast} wake={wakeRaw} />}
    {modal?.type === 'pair' && <Pair pc={modal.pc} close={() => setModal(null)} paired={save} toast={toast} />}
    {modal?.type === 'remote' && <Remote pc={modal.pc} preview={modal.preview} close={() => setModal(null)} toast={toast} />}
    {modal?.type === 'detail' && <Modal title={modal.pc.name} close={() => setModal(null)}><div className="modal-body"><div className="detail-info"><Monitor size={36} /><p>{modal.pc.ip || 'Chưa lưu IP'}<br /><small>{modal.pc.mac}</small></p></div><div className="detail-menu"><Button icon={Pencil} onClick={() => setModal({ type: 'setup', pc: modal.pc })}>Chỉnh sửa / Quét lại</Button><Button icon={Link2} onClick={() => setModal({ type: 'pair', pc: modal.pc })}>{modal.pc.agentPaired ? 'Ghép lại Windows Agent' : 'Ghép nối Windows Agent'}</Button>{modal.pc.agentPaired && <Button onClick={async () => { try { await forgetCode(modal.pc.id); save({ ...modal.pc, agentPaired: false }); setModal(null); } catch (e) { toast(e.message); } }}>Quên ghép nối</Button>}<Button icon={MousePointer2} onClick={() => setModal({ type: 'remote', pc: modal.pc, preview: !modal.pc.agentPaired })}>Điều khiển{!modal.pc.agentPaired && ' · Xem trước'}</Button><Button icon={Moon} disabled={!!busy[modal.pc.id]} onClick={() => powerDialog(modal.pc, 'sleep')}>Sleep</Button><Button icon={Power} disabled={!!busy[modal.pc.id]} onClick={() => powerDialog(modal.pc, 'shutdown')}>Tắt máy</Button><Button icon={CircleHelp} onClick={() => setModal({ type: 'diagnostics', pc: modal.pc })}>Chẩn đoán kết nối</Button><Button icon={Trash2} className="danger" onClick={() => setModal({ type: 'delete', pc: modal.pc })}>Xóa máy tính</Button></div>{modal.pc.lastWake && <small>Lần Wake gần nhất: {new Date(modal.pc.lastWake).toLocaleString('vi-VN')}</small>}</div></Modal>}
    {modal?.type === 'diagnostics' && <Modal title="Chẩn đoán kết nối" close={() => setModal(null)}><div className="modal-body"><Help pc={modal.pc} lan={lan} /></div></Modal>}
    {modal?.type === 'history' && <Modal title="Lịch sử hoạt động" close={() => setModal(null)}><div className="modal-body history">{history.length ? history.map((item, i) => <div key={i}><Clock3 size={17} /><span>{item.text}<small>{new Date(item.at).toLocaleString('vi-VN')}</small></span></div>) : <p>Chưa có hoạt động.</p>}</div></Modal>}
    {modal?.type === 'power' && <Modal title={(modal.command === 'sleep' ? 'Sleep ' : 'Tắt máy ') + modal.pc.name + '?'} close={() => setModal(null)}><div className="modal-body"><p>Lưu công việc trên PC trước khi tiếp tục. Agent chờ 10 giây trước khi thực hiện; bạn có thể hủy trong ứng dụng hoặc ở tray Windows.</p><p className="muted">Phản hồi chỉ xác nhận đã lên lịch, không khẳng định PC đã Sleep/tắt.</p></div><footer><Button onClick={() => setModal(null)}>Quay lại</Button><Button className="danger" onClick={() => void power(modal.pc, modal.command)}>Xác nhận {modal.command === 'sleep' ? 'Sleep' : 'tắt máy'}</Button></footer></Modal>}
    {modal?.type === 'delete' && <Modal title={'Xóa ' + modal.pc.name + '?'} close={() => setModal(null)}><div className="modal-body"><p>Xóa thông tin máy và mã ghép nối khỏi trình duyệt này.</p></div><footer><Button onClick={() => setModal(null)}>Giữ lại</Button><Button className="danger" onClick={async () => { try { if (modal.pc.agentPaired) await forgetCode(modal.pc.id); stopWake(modal.pc); setPcs(p => p.filter(v => v.id !== modal.pc.id)); log('Đã xóa ' + modal.pc.name); setModal(null); } catch (e) { toast(e.message); } }}>Xóa máy tính</Button></footer></Modal>}
    {modal?.type === 'wakeResult' && <Modal title="PC đã bật chưa?" close={() => setModal(null)}><div className="modal-body"><p>{modal.pc.name} chưa phản hồi{!modal.pc.ip && ' vì chưa lưu địa chỉ IP'}. Điều này không có nghĩa PC chắc chắn đã tắt.</p></div><footer><Button onClick={() => pcNotStarted(modal.pc)}>Chưa bật · Trợ giúp</Button><Button className="primary" onClick={() => { stopWake(modal.pc); setManual(p => ({ ...p, [modal.pc.id]: true })); setModal(null); log('Xác nhận thủ công PC đã bật: ' + modal.pc.name); }}>Đã bật</Button></footer></Modal>}
  </div>;
}
class ErrorBoundary extends React.Component {
  state = { error: null };
  static getDerivedStateFromError(error) { return { error }; }
  render() { return this.state.error ? <div className="fatal"><h1>Không mở được dữ liệu</h1><p>Kiểm tra trình duyệt có cho phép lưu dữ liệu website và tải lại trang.</p><button onClick={() => location.reload()}>Tải lại</button></div> : this.props.children; }
}
createRoot(document.getElementById('root')).render(<ErrorBoundary><App /></ErrorBoundary>);
