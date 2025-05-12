# Panduan Penggunaan Fungsi OLED Display untuk Proyek Smart Monitoring Temperature Room

## Pendahuluan
Dokumen ini berisi petunjuk penggunaan fungsi-fungsi yang telah diimplementasikan untuk menampilkan data pada display OLED SSD1306. Fungsi-fungsi ini dapat digunakan untuk menampilkan judul, nilai suhu, dan nilai kelembaban pada layar OLED.

## Daftar Fungsi Utama

### 1. Inisialisasi OLED
```assembly
; Memanggil fungsi untuk inisialisasi display OLED
RCALL I2C_init         ; Inisialisasi I2C bus
RCALL SSD1306_init     ; Inisialisasi OLED display
RCALL clear_screen     ; Bersihkan layar
```

### 2. Menampilkan Teks Statis (Judul)
```assembly
; Menampilkan judul/teks statis
RCALL display_static_text
```

### 3. Menampilkan Suhu
```assembly
; Untuk menampilkan nilai suhu
; Sebelum memanggil, pastikan nilai suhu disimpan di register R25
LDI   R25, [NILAI_SUHU]  ; Ganti [NILAI_SUHU] dengan nilai dari sensor DHT
RCALL display_temperature
```

### 4. Menampilkan Kelembaban
```assembly
; Untuk menampilkan nilai kelembaban
; Sebelum memanggil, pastikan nilai kelembaban disimpan di register R26
LDI   R26, [NILAI_KELEMBABAN]  ; Ganti [NILAI_KELEMBABAN] dengan nilai dari sensor DHT
RCALL display_humidity
```

### 5. Ekspektasi saat program dijalankan
![Screen Recording 2025-05-12 222346](https://github.com/user-attachments/assets/fc70f7d6-e0d1-4047-bbda-7e65f630a533)

## Cara Mengintegrasikan dengan Sensor DHT

1. Jeremy perlu menyimpan nilai suhu yang dibaca dari sensor DHT ke register R25
2. Nilai kelembaban (jika dibutuhkan) disimpan ke register R26
3. Panggil fungsi `display_temperature` dan `display_humidity` untuk memperbarui tampilan

```assembly
; Contoh integrasi dengan pembacaan sensor DHT
read_dht:
    ; Kode untuk membaca sensor DHT di sini
    ; ...
    
    ; Simpan nilai suhu dan kelembaban ke register
    MOV   R25, [REG_SUHU]        ; Simpan nilai suhu ke R25
    MOV   R26, [REG_KELEMBABAN]  ; Simpan nilai kelembaban ke R26
    
    ; Update tampilan
    RCALL display_temperature
    RCALL display_humidity
    RET
```

## Cara Mengintegrasikan dengan Threshold Potentiometer

Untuk menampilkan nilai threshold (ambang batas) suhu pada OLED, buat fungsi tambahan:

```assembly
; Contoh implementasi untuk menampilkan threshold atas dan bawah
display_thresholds:
    ; Asumsi:
    ; R27 = nilai threshold atas
    ; R28 = nilai threshold bawah
    
    ; Set posisi kursor untuk threshold atas (contoh: baris 6)
    LDI   R20, 6           ; Page 6
    LDI   R21, 32          ; Column 32
    RCALL set_cursor
    
    ; Tampilkan "MAX:" dan nilai threshold atas
    ; Implementasi mirip dengan display_temperature
    ; ...
    
    ; Set posisi kursor untuk threshold bawah (contoh: baris 7)
    LDI   R20, 7           ; Page 7
    LDI   R21, 32          ; Column 32
    RCALL set_cursor
    
    ; Tampilkan "MIN:" dan nilai threshold bawah
    ; Implementasi mirip dengan display_temperature
    ; ...
    
    RET
```

## Cara Menggunakan I2C untuk Komunikasi Master-Slave

Rafif perlu menggunakan fungsi I2C yang telah diimplementasikan untuk komunikasi:

1. Inisialisasi I2C dengan `RCALL I2C_init` pada master dan slave
2. Pada slave, gunakan fungsi I2C untuk mengirim data suhu dan kelembaban
3. Pada master, terima data tersebut dan gunakan register R25 dan R26 untuk menyimpan nilainya
4. Panggil fungsi display untuk menampilkan data pada OLED

## Catatan Penting

1. **Jangkauan Nilai**: Fungsi display bekerja untuk nilai 0-99 (dua digit)
2. **Penggunaan Register**:
   - R25: Nilai suhu
   - R26: Nilai kelembaban
   - R27/R28: Dapat digunakan untuk threshold atas/bawah
3. **Refresh Rate**: Tambahkan delay yang cukup antara update tampilan (gunakan `delay_long`)
4. **Penghematan Memori**: Gunakan `display_temperature` dan `display_humidity` hanya saat nilai berubah

## Contoh Loop Utama

```assembly
main_loop:
    ; Baca data dari slave melalui I2C
    RCALL read_slave_data
    
    ; Update tampilan OLED
    RCALL display_temperature
    RCALL display_humidity
    RCALL display_thresholds
    
    ; Delay untuk stabilitas tampilan
    RCALL delay_long
    RCALL delay_long
    
    ; Lanjutkan loop
    RJMP main_loop
```

## Troubleshooting

1. **Layar Tidak Menampilkan Apa-apa**: Pastikan inisialisasi I2C dan OLED benar
2. **Nilai Tidak Akurat**: Periksa konversi nilai dari sensor DHT
3. **Tampilan Tidak Update**: Pastikan register R25/R26 diperbarui dengan nilai baru

Semoga berhasil menyelesaikan proyek Smart Monitoring Temperature Room!
