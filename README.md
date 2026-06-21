# Ollama Setup — T4n OS

Script automation untuk install dan uninstall Ollama di T4n OS (Void Linux),
diarahkan sepenuhnya ke partisi root (`/opt/ollama`) agar tidak memakan
ruang di partisi `/home`.

## Spesifikasi Target

Dioptimalkan dan diuji untuk:

- **Laptop**: Lenovo IdeaPad Slim 3 14IU7
- **CPU**: Intel Core i3-1215U (CPU only, tanpa GPU dedicated)
- **RAM**: 16 GB (efektif ~12–13 GB karena shared dengan iGPU)
- **OS** : T4n OS (berbasis Void Linux, init system **runit**)

## Model yang Diinstal

| Model             | Ukuran | Kegunaan                                           |
|-------------------|--------|----------------------------------------------------|
| `qwen2.5-code:7b` | 4.7 GB | Coding Assistant - Autocomplete, Review, Debugging |
| `deepseek-r1:8b`  | 5.2 GB | Ethical Hacking - Security, Pentest, Reasoning     |

> Kedua model dipilih agar tetap nyaman dijalankan di CPU i3-1215U
> tanpa GPU. Hindari model 14B ke atas pada spek ini — terlalu lambat
> untuk pemakaian interaktif (estimasi 2–4 token/detik).

## Lokasi Instalasi

Semua diarahkan ke partisi root, **tidak menyentuh `/home`**:

```
/opt/ollama/bin/        # binary ollama
/opt/ollama/lib/        # library pendukung
/opt/ollama/models/     # model yang di-pull (OLLAMA_MODELS)
/etc/sv/ollama/         # definisi service runit
```

Service di-link ke direktori yang benar-benar di-scan oleh `runsvdir`
di Void Linux:

```
/etc/runit/runsvdir/default/ollama -> /etc/sv/ollama
```

## Instalasi
### Prasyarat

- Akses `sudo`/root
- Koneksi internet (download ~1.3 GB untuk binary, + ukuran model)
- `zstd` terinstall (untuk extract archive `.tar.zst`):
  ```bash
  sudo xbps-install -S zstd
  ```

### Menjalankan

```bash
chmod +x install-ollama.sh
sudo ./install-ollama.sh
```

### Apa yang Dilakukan Script

1. Membuat direktori `/opt/ollama` dan `/opt/ollama/models`
2. Download binary Ollama (`.tar.zst`) dan extract ke `/opt/ollama`
3. Menambahkan environment variable (`PATH`, `LD_LIBRARY_PATH`,
   `OLLAMA_MODELS`) ke `~/.bashrc`, `~/.zshrc`, dan
   `~/.config/fish/config.fish` milik user yang menjalankan `sudo`
4. Membuat service runit di `/etc/sv/ollama` dan link ke
   `/etc/runit/runsvdir/default`
5. Menunggu service `up` (dicek lewat `curl http://127.0.0.1:11434`)
6. Pull `qwen2.5-coder:7b` dan `xploiter/pentester` (dengan retry
   otomatis 3x bila gagal karena jaringan)
7. Mengembalikan ownership `/opt/ollama` ke user biasa (bukan root)

### Setelah Instalasi

```bash
source ~/.bashrc , ~/.zshrc atau ~/.config/fish/config.fish  # atau buka terminal baru
ollama run qwen2.5-coder:7b
ollama run deepseek-r1:8b
```

## Uninstall

```bash
chmod +x uninstall-ollama.sh

# Hapus total (binary + model)
sudo ./uninstall-ollama.sh

# Hapus binary saja, model tetap disimpan
sudo ./uninstall-ollama.sh --keep-models
```

### Apa yang Dibersihkan

- Proses `ollama serve` yang sedang berjalan
- Service runit (`/etc/sv/ollama` dan symlink-nya)
- `/opt/ollama` (binary, lib, model — kecuali pakai `--keep-models`)
- Blok environment variable di `.bashrc` / `.zshrc` / `config.fish`
- SSH key (`id_ed25519`) yang otomatis dibuat Ollama di `/root/.ollama`

## Mengelola Service Manual

```bash
sudo sv status ollama     # cek status
sudo sv start ollama      # nyalakan
sudo sv down ollama       # matikan
sudo sv restart ollama    # restart
```

Untuk debug langsung tanpa lewat runit:

```bash
sudo sh /etc/sv/ollama/run
```

## Troubleshooting

### `curl: Failed to connect to 127.0.0.1 port 11434`
Service belum naik. Cek `sudo sv status ollama`, lalu jalankan manual
`sudo sh /etc/sv/ollama/run` untuk lihat error langsung di terminal.

### `gzip: stdin: not in gzip format`
Build Ollama terbaru menggunakan format `.tar.zst`, bukan `.tgz`.
Pastikan `URL` di script mengarah ke `ollama-linux-amd64.tar.zst` dan
`zstd` sudah terinstall.

### Service `down` terus padahal `sudo sh /etc/sv/ollama/run` jalan normal
Biasanya karena environment yang diterima `runsv` jauh lebih minim
dari shell interaktif (`$HOME` tidak ter-set). Script `run` sudah
menambahkan `export HOME=/root` secara eksplisit untuk menghindari ini.

### `dial tcp: lookup registry.ollama.ai ... network is unreachable`
DNS/koneksi belum stabil tepat saat proses pull dimulai. Script sudah
menambah jeda 5 detik + retry otomatis 3x. Jika masih gagal, jalankan
manual: `ollama pull <model>`.

### Service lain (PipeWire, dll) ikut terganggu setelah menjalankan script
Pada versi awal pengembangan, script sempat menggunakan
`pkill -HUP runsvdir` untuk memaksa `runsvdir` membaca service baru.
Perintah ini ternyata mengirim sinyal **global** dan memicu restart
seluruh service runit di sistem, termasuk dependency PipeWire. Versi
script saat ini **tidak lagi** menggunakan signal tersebut — diganti
dengan polling pasif terhadap `supervise/ok`.

## > [!NOTE]
> Jangan jalankan dua model besar bersamaan di spek CPU-only 16 GB — muat satu per satu sesuai kebutuhan.

<div align="center">

[@T4n-Labs](https://t4n-labs.github.io/site) · [@Gh0sT4n](https://gh0st4n.github.io/site)

</div>
