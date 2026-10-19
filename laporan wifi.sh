#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Harap jalankan script ini sebagai root (sudo ./install-wifi-final.sh)"
  exit 1
fi

echo "=========================================================="
echo "1. MEMPERBAIKI ERROR APT (CONFLICTING VALUES)..."
echo "=========================================================="
# Menghapus paksa semua repository dan key NodeSource yang bentrok
rm -f /etc/apt/sources.list.d/nodesource.list
rm -f /etc/apt/keyrings/nodesource.gpg
rm -f /usr/share/keyrings/nodesource.gpg
apt-get clean
apt-get update -y

echo "=========================================================="
echo "2. MEMBERSIHKAN LAYANAN & APLIKASI LAMA..."
echo "=========================================================="
systemctl stop wifi-8081 wifi-8082 2>/dev/null || true
systemctl disable wifi-8081 wifi-8082 2>/dev/null || true
rm -f /etc/systemd/system/wifi-8081.service /etc/systemd/system/wifi-8082.service
systemctl daemon-reload
rm -rf /opt/wifi-8081 /opt/wifi-8082

apt-get remove --purge -y libnode-dev nodejs npm 2>/dev/null || true
apt-get autoremove -y
apt-get --fix-broken install -y

echo "=========================================================="
echo "3. MENGINSTAL NODE.JS 20 (OFFICIAL) & SQLITE3..."
echo "=========================================================="
apt-get install -y ca-certificates curl gnupg build-essential sqlite3 python3

mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update -y
apt-get install -y nodejs

# Pengecekan Node.js
NODE_BIN=$(which node)
if [ -z "$NODE_BIN" ]; then
    echo "GAGAL MENGINSTAL NODEJS! Silakan cek koneksi internet atau repository."
    exit 1
fi

echo "=========================================================="
echo "4. MENYUSUN KODE APLIKASI WEB..."
echo "=========================================================="
cat << 'EOF' > /tmp/server.js
const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const session = require('express-session');
const app = express();

const PORT = process.env.PORT || 8081;
const PEMBAGI = parseInt(process.env.PEMBAGI) || 3;

app.use(express.urlencoded({ extended: true }));
app.use(session({ secret: 'super-rahasia-wifi', resave: false, saveUninitialized: true }));

const db = new sqlite3.Database('./database.db');
db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS transaksi (id INTEGER PRIMARY KEY AUTOINCREMENT, tahun TEXT, bulan TEXT, tanggal TEXT, ket TEXT, tipe TEXT, harga REAL, qty INTEGER, total REAL)`);
    db.run(`CREATE TABLE IF NOT EXISTS master_tahun (tahun TEXT UNIQUE)`);
    db.run(`CREATE TABLE IF NOT EXISTS master_bulan (kode TEXT UNIQUE, nama TEXT)`);
});

app.get('/', (req, res) => res.redirect('/view'));

app.get('/login', (req, res) => {
    res.send(`
    <!DOCTYPE html><html><head><meta charset='utf-8'><title>Login Admin</title>
    <style>body{font-family:Arial;background:#eef2f3;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;} .box{background:#fff;padding:30px;border-radius:8px;box-shadow:0 4px 10px rgba(0,0,0,0.1);width:320px;text-align:center;} input,button{width:100%;padding:12px;margin-bottom:10px;box-sizing:border-box;border-radius:4px;border:1px solid #ccc;} button{background:#007bff;color:#fff;border:none;font-weight:bold;cursor:pointer;padding:12px;font-size:16px;}</style></head>
    <body><div class='box'><h2>🔐 Login Admin</h2>
    <form method='POST' action='/login'>
        <input type='text' name='user' placeholder='Username' required>
        <input type='password' name='pass' placeholder='Password' required>
        <button type='submit'>Masuk Sistem</button>
    </form></div></body></html>`);
});

app.post('/login', (req, res) => {
    if(req.body.user === 'admin' && req.body.pass === 'Setya2018') {
        req.session.admin = true;
        res.redirect('/admin');
    } else {
        res.send("<script>alert('Login Salah!');window.location='/login';</script>");
    }
});

function checkAuth(req, res, next) {
    if(req.session.admin) return next();
    res.redirect('/login');
}

function render(req, res, isAdmin) {
    let filterTahun = req.query.tahun || "";
    let filterBulan = req.query.bulan || "";

    db.all("SELECT * FROM master_tahun ORDER BY tahun ASC", (err, tRows) => {
        db.all("SELECT * FROM master_bulan ORDER BY kode ASC", (err, bRows) => {
            let q = "SELECT * FROM transaksi WHERE 1=1";
            let p = [];
            if(filterTahun) { q += " AND tahun=?"; p.push(filterTahun); }
            if(filterBulan) { q += " AND bulan=?"; p.push(filterBulan); }
            q += " ORDER BY tanggal DESC, id DESC";

            db.all(q, p, (err, txRows) => {
                let tIn = 0, tOut = 0;
                if(txRows) {
                    txRows.forEach(x => {
                        if(x.tipe === 'Pendapatan') tIn += x.total;
                        if(x.tipe === 'Pengeluaran') tOut += x.total;
                    });
                }
                let laba = tIn - tOut;
                let bagi = laba / PEMBAGI;

                let h = `
                <!DOCTYPE html><html><head><meta charset='utf-8'><title>Laporan Keuangan WiFi</title>
                <style>
                body{font-family:Arial;background:#f4f7f6;color:#333;padding:20px;} 
                .card{background:#fff;padding:20px;border-radius:8px;box-shadow:0 2px 5px rgba(0,0,0,0.05);margin-bottom:20px;} 
                .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;} 
                table{width:100%;border-collapse:collapse;} th,td{border:1px solid #ddd;padding:10px;text-align:left;} th{background:#eee;} 
                .btn{padding:8px 15px;background:#007bff;color:#fff;text-decoration:none;border-radius:4px;border:none;cursor:pointer;} 
                .btn-red{background:#dc3545;} 
                .btn-out{border:1px solid #007bff;color:#007bff;text-decoration:none;padding:5px 12px;border-radius:15px;display:inline-block;margin:3px;font-size:14px;} 
                .active{background:#007bff;color:#fff;} 
                input,select{padding:10px;border:1px solid #ccc;border-radius:4px;width:100%;box-sizing:border-box;} 
                .f-note{background:#fff3cd;color:#856404;padding:15px;text-align:center;font-weight:bold;border-radius:8px;margin-top:30px;font-size:15px;}
                </style></head>
                <body><div style='max-width:1100px;margin:auto;'>
                
                <div style='display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;border-bottom:2px solid #eee;padding-bottom:15px;'>
                    <h2 style='margin:0;'>${isAdmin ? "🛠️ Administrator" : "👀 Layar View Publik"} - Port ${PORT}</h2>
                    ${isAdmin ? `<div><a href='/view' target='_blank' class='btn' style='background:#17a2b8;'>Buka View Publik</a> <a href='/logout' class='btn btn-red'>Logout Admin</a></div>` : ''}
                </div>
                
                <div class='grid' style='margin-bottom:20px;'>
                    <div class='card' style='border-top:4px solid #28a745'>Total Pendapatan<br><h3>Rp ${tIn.toLocaleString('id-ID')}</h3></div>
                    <div class='card' style='border-top:4px solid #dc3545'>Total Pengeluaran<br><h3>Rp ${tOut.toLocaleString('id-ID')}</h3></div>
                    <div class='card' style='border-top:4px solid #17a2b8'>Hasil Bersih<br><h3>Rp ${laba.toLocaleString('id-ID')}</h3></div>
                    <div class='card' style='border-top:4px solid #ffc107'>Hasil / ${PEMBAGI} Investor<br><h3>Rp ${bagi.toLocaleString('id-ID')}</h3></div>
                </div>

                <div class='card' style='background:#fafafa;'>
                    <strong>📅 Filter Tahun:</strong> <a href='?tahun=&bulan=${filterBulan}' class='btn-out ${!filterTahun?"active":""}'>Semua Tahun</a>
                    ${(tRows||[]).map(y => `<a href='?tahun=${y.tahun}&bulan=${filterBulan}' class='btn-out ${filterTahun===y.tahun?"active":""}'>${y.tahun}</a>`).join('')}
                    <br><br>
                    <strong>🗓️ Filter Bulan:</strong> <a href='?tahun=${filterTahun}&bulan=' class='btn-out ${!filterBulan?"active":""}'>Semua Bulan</a>
                    ${(bRows||[]).map(b => `<a href='?tahun=${filterTahun}&bulan=${b.kode}' class='btn-out ${filterBulan===b.kode?"active":""}'>${b.nama}</a>`).join('')}
                </div>`;

                if(isAdmin) {
                    h += `
                    <div class='card grid' style='background:#eef2f5;'>
                        <div><strong>➕ Tambah Pilihan Tahun:</strong><form action='/add-thn' method='POST' style='display:flex;gap:5px;margin-top:10px;'><input type='text' name='thn' placeholder='Cth: 2028' required><button class='btn' style='background:#28a745;'>Simpan</button></form></div>
                        <div><strong>➕ Tambah Pilihan Bulan:</strong><form action='/add-bln' method='POST' style='display:flex;gap:5px;margin-top:10px;'><input type='text' name='kode' placeholder='Kd(01)' required style='width:70px;'><input type='text' name='nama' placeholder='Nama Bulan' required><button class='btn' style='background:#28a745;'>Simpan</button></form></div>
                    </div>
                    <div class='card'><h3>✍️ Input Transaksi Baru</h3><form action='/add-tx' method='POST' class='grid' style='align-items:end;'>
                        <div>Tahun<select name='tahun' required>${(tRows||[]).length>0 ? tRows.map(y=>`<option value='${y.tahun}'>${y.tahun}</option>`).join('') : `<option value=''>-- Tambah Tahun Dulu --</option>`}</select></div>
                        <div>Bulan<select name='bulan' required>${(bRows||[]).length>0 ? bRows.map(b=>`<option value='${b.kode}'>${b.nama}</option>`).join('') : `<option value=''>-- Tambah Bulan Dulu --</option>`}</select></div>
                        <div>Tanggal<input type='date' name='tgl' required></div>
                        <div>Tipe<select name='tipe' required><option value='Pendapatan'>Pendapatan</option><option value='Pengeluaran'>Pengeluaran</option></select></div>
                        <div style='grid-column:span 2;'>Keterangan<input type='text' name='ket' placeholder='Cth: Beli Kabel / Iuran' required></div>
                        <div>Harga Satuan (Rp)<input type='number' name='hrg' placeholder='Contoh: 50000' required></div>
                        <div>Qty (Jumlah)<input type='number' name='qty' value='1' required></div>
                        <div style='grid-column:1/-1;'><button class='btn' style='width:100%;font-size:16px;padding:12px;'>Simpan Transaksi Data</button></div>
                    </form></div>`;
                }

                h += `
                <div class='card'><h3>Riwayat Transaksi Keuangan</h3><div style='overflow-x:auto;'><table>
                <tr><th>Thn/Bln</th><th>Tanggal</th><th>Keterangan</th><th>Tipe</th><th>Harga Satuan</th><th>Qty</th><th>Total Nominal</th>${isAdmin?"<th>Aksi</th>":""}</tr>
                ${(txRows||[]).length>0 ? txRows.map(x => {
                    let nB = x.bulan;
                    if(bRows) { let f = bRows.find(b=>b.kode===x.bulan); if(f) nB=f.nama; }
                    let wrn = x.tipe==='Pendapatan' ? 'green' : 'red';
                    return `<tr><td>${x.tahun} /${nB}</td><td>${x.tanggal}</td><td>${x.ket}</td><td style='color:${wrn};font-weight:bold;'>${x.tipe}</td><td>Rp ${x.harga.toLocaleString('id-ID')}</td><td>${x.qty}</td><td><strong>Rp ${x.total.toLocaleString('id-ID')}</strong></td>${isAdmin?`<td><a href='/del-tx/${x.id}' class='btn btn-red' style='padding:5px 10px;' onclick='return confirm("Yakin ingin menghapus data ini?")'>Hapus</a></td>`:''}</tr>`;
                }).join('') : `<tr><td colspan='${isAdmin?8:7}' style='text-align:center;'>Belum ada data pada periode ini</td></tr>`}
                </table></div></div>
                <div class='f-note'>tolong di bantu koreksi ya barang kali ada yang salah</div>
                </div></body></html>`;
                res.send(h);
            });
        });
    });
}

app.get('/admin', checkAuth, (req, res) => render(req, res, true));
app.get('/view', (req, res) => render(req, res, false));
app.get('/logout', (req, res) => { req.session.admin = false; res.redirect('/view'); });

app.post('/add-tx', checkAuth, (req, res) => {
    let hrg = parseFloat(req.body.hrg) || 0;
    let qty = parseInt(req.body.qty) || 1;
    let tot = hrg * qty;
    db.run("INSERT INTO transaksi (tahun, bulan, tanggal, ket, tipe, harga, qty, total) VALUES (?,?,?,?,?,?,?,?)", [req.body.tahun, req.body.bulan, req.body.tgl, req.body.ket, req.body.tipe, hrg, qty, tot], () => res.redirect('back'));
});
app.post('/add-thn', checkAuth, (req, res) => db.run("INSERT OR IGNORE INTO master_tahun (tahun) VALUES (?)", [req.body.thn], () => res.redirect('back')));
app.post('/add-bln', checkAuth, (req, res) => db.run("INSERT OR IGNORE INTO master_bulan (kode, nama) VALUES (?,?)", [req.body.kode, req.body.nama], () => res.redirect('back')));
app.get('/del-tx/:id', checkAuth, (req, res) => db.run("DELETE FROM transaksi WHERE id=?", [req.params.id], () => res.redirect('back')));

app.listen(PORT, () => console.log('Ready on port ' + PORT));
EOF

echo "=========================================================="
echo "5. SETUP FOLDER APLIKASI..."
echo "=========================================================="
for PORT in 8081 8082; do
    mkdir -p /opt/wifi-$PORT
    cd /opt/wifi-$PORT
    cat << 'PKG' > package.json
{
  "name": "wifi-app",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2",
    "express-session": "^1.18.0",
    "sqlite3": "^5.1.7"
  }
}
PKG
    npm install --omit=dev
    cp /tmp/server.js ./server.js
done

echo "=========================================================="
echo "6. MENGHIDUPKAN SERVER..."
echo "=========================================================="
cat << EOF > /etc/systemd/system/wifi-8081.service
[Unit]
Description=WiFi App 8081
After=network.target
[Service]
User=root
WorkingDirectory=/opt/wifi-8081
Environment="PORT=8081"
Environment="PEMBAGI=3"
ExecStart=$NODE_BIN server.js
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/wifi-8082.service
[Unit]
Description=WiFi App 8082
After=network.target
[Service]
User=root
WorkingDirectory=/opt/wifi-8082
Environment="PORT=8082"
Environment="PEMBAGI=2"
ExecStart=$NODE_BIN server.js
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wifi-8081 wifi-8082
systemctl restart wifi-8081 wifi-8082

echo "=========================================================="
echo "✅ INSTALASI BERHASIL!"
echo "Server sudah menyala menggunakan path: $NODE_BIN"
echo "=========================================================="