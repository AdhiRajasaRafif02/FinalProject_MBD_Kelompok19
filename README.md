# <span style="color:yellow; font-weight:bold"> Final Project MBD - </span> Smart System Monitoring</b>

## 1. Introduction to the problem and the solution 
Dalam sebuah ruangan tertutup, penting untuk mengetahui kondisi suhu secara real-time guna memastikan kenyamanan, efisiensi energi, dan keamanan perangkat maupun individu yang berada di dalamnya. Tanpa sistem pemantauan yang andal, perubahan suhu yang signifikan bisa terjadi tanpa terdeteksi, yang berpotensi menimbulkan dampak negatif seperti kerusakan perangkat elektronik, gangguan kesehatan, atau ketidakefisienan sistem pendingin udara. Oleh karena itu, dibutuhkan suatu sistem yang mampu melakukan monitoring suhu secara otomatis, akurat, dan berkelanjutan agar kondisi lingkungan di dalam ruangan dapat selalu berada dalam batas yang diinginkan (threshold) sesuai standar yang telah ditentukan.

Untuk menjawab kebutuhan tersebut, dirancanglah sebuah proyek Smart Monitoring Temperature System yang berfungsi mendeteksi dan menampilkan suhu serta kelembapan ruangan secara real-time. Sistem ini dilengkapi dengan fitur penetapan ambang batas suhu (threshold) yang dapat ditampilkan melalui layar OLED sebagai referensi pengguna. Ketika suhu ruangan terdeteksi melebihi batas yang telah ditentukan, sistem akan memberikan peringatan secara langsung kepada pengguna, sehingga dapat dilakukan tindakan yang tepat untuk menjaga kestabilan suhu.

## 2. Hardware design and implementation details
![picture 1](https://i.imgur.com/dA8AyoV.png)  

Pada rangkaian diatas, terdapat 2 Arduino yang berperan sebagai MASTER dan SLAVE. Master Arduino memiliki komponen arduino seperti LED, buzzer, potentiometer, dan OLED. Pada Slave Arduino terdapat serial monitor atau virtual monitor dan sensor DHT11.  
### Master Arduino:
- **LED**  
LED akan berperan sebagai penanda ketika suhu melewati nilai threshold yang diberikan oleh potentiometer. Ketika nilai suhu berada di range y-3 <= x < y dengan y adalah nilai threshold, maka LED akan menyala dan mati masing-masing selama 1 detik (kedap kedip). Namun ketika diatas sama dengan nilai threshold, maka LED akan menyala terus.
- **Buzzer**  
Buzzer berperan sebagai penanda ketika suhu melewati nilai threshold pada potentiometer. Buzzer akan menyala (berbunyi) ketika suhu melewati nilai threshold.
- **Potentiometer**  
Potentiometer berperan sebagai pengatur nilai threshold dimana nilai threshold berada di range 25 hingga 40. Perhitungan nilai analog 0-1023 dan di konversi menjadi nilai suhu 25-40 dalam celcius.
- **OLED**  
OLED akan menampilkan nilai suhu, kelembapan, dan status dari hubungan suhu dengan threshold. 

### Slave Arduino
- **Serial Monitor**  
Serial monitor akan menampilkan nilai suhu dan kelembapan. Perbedaannya dengan OLED, serial monitor tidak menampilkan status dan nilai suhu & kelembapan dapat dilihat dari Slave Arduino
- **Sensor DHT11**  
Sensor DHT11 merupakan sensor suhu kelembapan yang dapat mendapatkan nilai suhu dalam bentuk analog yang nantinya akan dikonversi menjadi digital (1-wire) dan nilainya akan ditampilkan dalam serial monitor (Slave Monitor) dan OLED (Master Arduino).

## 3. Software implementation details 

### OLED

### a. Menampilkan Teks Statis (Judul)
```assembly
; Menampilkan judul/teks statis
RCALL display_static_text
```

### b. Menampilkan Suhu
```assembly
; Untuk menampilkan nilai suhu
; Sebelum memanggil, pastikan nilai suhu disimpan di register R25
LDI   R25, [NILAI_SUHU]  ; Ganti [NILAI_SUHU] dengan nilai dari sensor DHT
RCALL display_temperature
```

### c. Menampilkan Kelembaban
```assembly
; Untuk menampilkan nilai kelembaban
; Sebelum memanggil, pastikan nilai kelembaban disimpan di register R26
LDI   R26, [NILAI_KELEMBABAN]  ; Ganti [NILAI_KELEMBABAN] dengan nilai dari sensor DHT
RCALL display_humidity
```

### d. Ekspektasi saat program dijalankan
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

### 4. Test results and performance evaluation 




