# Hardware Monitor

Aplikasi menu bar macOS yang ringan untuk memantau suhu CPU, memori, dan GPU.

Menu bar menampilkan CPU, GPU, dan RAM bertumpuk dalam satu kolom selebar ±55 pt
(font 9 pt; 8 pt di menu bar 24 pt). Angka berwarna oranye ≥ 80 °C, merah ≥ 95 °C,
RAM ikut berwarna saat tekanan memori tinggi. Klik untuk rincian: suhu rata-rata/maks, pemakaian GPU,
rincian memori, swap, interval refresh (1/2/5 detik). Geser posisinya dengan ⌘-drag.

## Build & instal

```bash
./scripts/install.sh    # build, ganti /Applications/Hardware Monitor.app, lalu jalankan
./scripts/bundle.sh     # hanya build → build/Hardware Monitor.app
```

Untuk berjalan otomatis setelah login, centang **Buka saat login** di menu aplikasi
(memakai `SMAppService`; terlihat juga di Pengaturan Sistem → Umum → Login Items).
Aktifkan dari salinan di `/Applications`, karena macOS mendaftarkan lokasi aplikasi yang sedang berjalan.

## Validasi sensor

Nilai suhu di luar 10–130 °C, atau lebih dari 25 °C di bawah median kelompoknya, dibuang;
key tersebut memakai nilai valid terakhirnya. Setelah Mac bangun dari sleep, pembacaan ditunda 5 detik
lalu semua key dibaca ulang. Nilai yang dibuang dicatat ke log:

```bash
log show --last 1d --predicate 'subsystem == "local.HardwareMonitor"' --style compact
```

## Probe sensor

```bash
swift build
.build/debug/SensorProbe          # ringkasan semua pembaca + waktu baca
.build/debug/SensorProbe --hid    # sensor suhu lewat IOHID
.build/debug/SensorProbe --smc    # semua key suhu SMC (KEY<tab>°C)
.build/debug/SensorProbe --bench  # waktu nyata vs waktu CPU per pembacaan suhu
.build/debug/SensorProbe --watch 60  # pantau semua key CPU/GPU, laporkan nilai < 20 °C
```

## Struktur

| Path | Isi |
|---|---|
| `Sources/CPrivate` | Deklarasi C untuk API privat (IOHID event, struct AppleSMC) |
| `Sources/Sensors` | `SMCReader`, `ThermalReader`, `MemoryReader`, `GPUReader`, `TemperatureReader` (IOHID) |
| `Sources/HardwareMonitor` | Aplikasi menu bar (AppKit `NSStatusItem`) |
| `Sources/SensorProbe` | CLI untuk menguji pembaca |
| `Support/Info.plist` | `LSUIElement` (tanpa ikon Dock) |

## Footprint (release, M2, interval 2 detik)

| | Awal | Sekarang |
|---|---|---|
| Waktu CPU per pembacaan suhu | 0,87 ms (36 key) | 0,13 ms (9 key bergiliran) |
| CPU rata-rata (diukur 120 detik) | ±0,2% | ±0,08% |
| Memory footprint | 11 MB | 11 MB |

Optimasi yang dipakai:
- `ThermalReader` membaca ¼ key SMC per tick secara bergiliran (semua key segar tiap 4 tick).
- `TitleView` menggambar judul langsung, menghindari Auto Layout yang dipicu `button.attributedTitle`.
- Lebar item dikunci, judul hanya digambar ulang jika nilainya berubah, rincian menu hanya dihitung saat menu terbuka.
- Timer berhenti saat layar mati; `malloc_zone_pressure_relief` setelah startup dan setelah menu ditutup.

Batas bawah RAM: aplikasi AppKit kosong yang hanya menampilkan satu status item sudah memakai ±9 MB.

## Temuan Fase 0 (Apple M2, macOS 26.3)

**IOHID** hanya mengekspos sensor die SoC (`PMU tdie1-8`, `PMU2 tdie1-8`), NAND, dan baterai.
Tidak ada sensor berlabel CPU/GPU (`pACC`, `eACC`, `GPU MTR`), jadi suhu per komponen diambil dari **SMC**.

Uji beban CPU 15 detik (8× `yes`), rata-rata per kelompok key SMC:

| Kelompok | Jumlah | Idle | Beban CPU | Kenaikan | Dipakai untuk |
|---|---|---|---|---|---|
| `Tp*` | 27 | 38.0 °C | 58.4 °C | +20.4 | **CPU** (P-core) |
| `Te*` | 3 | 37.5 °C | 50.2 °C | +12.7 | CPU (E-core) |
| `Tg*` | 6 | 35.2 °C | 47.1 °C | +11.9 | **GPU** |
| `Ts*`, `Th*` | 32 | ~33.5 °C | ~46.7 °C | ~+13 | sensor SoC lain (tidak dipakai) |
| `TB*` | 3 | 29.8 °C | 29.8 °C | 0 | baterai |

Catatan:
- `Tg*` ikut naik saat beban CPU karena panas menyebar di satu die. Pemetaan GPU berdasarkan konvensi nama
  dan belum diuji dengan beban GPU.
- Daftar key berbeda di tiap chip (M1/M2/M3/M4), jadi aplikasi mengelompokkan berdasarkan awalan key
  (`Tp`, `Te`, `Tg`), bukan memakai daftar key yang ditulis langsung di kode.
- Rencana tampilan: rata-rata kelompok di menu bar, nilai maksimum di menu dropdown.
