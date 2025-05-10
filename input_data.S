; Power Monitoring dengan Arduino UNO (AVR Assembly)
; Membaca sensor tegangan dari pin A0
; Membaca sensor arus dari pin A1
; Menghitung daya (P = V * I) dengan 1 desimal
; Menampilkan hasil daya di Serial Monitor

.include "m328pdef.inc"        ; Include definisi untuk ATmega328P (Arduino UNO)

; Definisi konstanta
.equ BAUD_RATE = 9600          ; Baudrate untuk komunikasi serial
.equ F_CPU = 16000000          ; Frekuensi clock Arduino UNO

; Penghitungan UBRR untuk komunikasi serial
.equ UBRR_VALUE = F_CPU/(16*BAUD_RATE)-1

; Alokasi register
.def temp = r16                ; Register sementara
.def voltage = r17             ; Nilai tegangan
.def current = r18             ; Nilai arus
.def power_low = r19           ; Byte rendah nilai daya
.def power_high = r20          ; Byte tinggi nilai daya
.def decimal = r21             ; Bagian desimal dari daya
.def digit = r22               ; Digit untuk konversi ASCII

; Segment data
.dseg
message:        .byte 20       ; Buffer untuk pesan
power_str:      .byte 10       ; String untuk nilai daya

; Segment kode
.cseg
.org 0x0000                    ; Alamat reset
    rjmp setup                 ; Lompat ke setup

; Setup program
setup:
    ; Inisialisasi stack pointer
    ldi temp, HIGH(RAMEND)
    out SPH, temp
    ldi temp, LOW(RAMEND)
    out SPL, temp
    
    ; Setup ADC
    ldi temp, (1<<ADEN)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0) ; Enable ADC, prescaler = 128
    sts ADCSRA, temp
    ldi temp, (1<<REFS0)       ; AVCC sebagai referensi
    sts ADMUX, temp
    
    ; Setup UART untuk Serial Monitor
    ; Atur baud rate
    ldi temp, HIGH(UBRR_VALUE)
    sts UBRR0H, temp
    ldi temp, LOW(UBRR_VALUE)
    sts UBRR0L, temp
    
    ; Enable transmitter
    ldi temp, (1<<TXEN0)
    sts UCSR0B, temp
    
    ; Format: 8 data, 1 stop bit
    ldi temp, (1<<UCSZ01)|(1<<UCSZ00)
    sts UCSR0C, temp
    
    ; Jeda singkat untuk stabilisasi
    rcall delay_100ms

main_loop:
    ; Baca sensor tegangan (A0)
    ldi temp, (1<<REFS0)       ; AVCC referensi, pilih ADC0 (A0)
    sts ADMUX, temp
    
    ; Start konversi
    lds temp, ADCSRA
    ori temp, (1<<ADSC)
    sts ADCSRA, temp
    
wait_adc1:
    ; Tunggu konversi selesai
    lds temp, ADCSRA
    sbrc temp, ADSC
    rjmp wait_adc1
    
    ; Ambil hasil tegangan (untuk contoh: skala 0-255 saja)
    lds voltage, ADCL
    lds temp, ADCH          ; Baca ADCH untuk mereset flag ADC
    
    ; Baca sensor arus (A1)
    ldi temp, (1<<REFS0)|(1<<MUX0)  ; AVCC referensi, pilih ADC1 (A1)
    sts ADMUX, temp
    
    ; Start konversi
    lds temp, ADCSRA
    ori temp, (1<<ADSC)
    sts ADCSRA, temp
    
wait_adc2:
    ; Tunggu konversi selesai
    lds temp, ADCSRA
    sbrc temp, ADSC
    rjmp wait_adc2
    
    ; Ambil hasil arus (untuk contoh: skala 0-255 saja)
    lds current, ADCL
    lds temp, ADCH          ; Baca ADCH untuk mereset flag ADC
    
    ; Hitung daya: P = V * I (sederhana dengan 1 angka di belakang koma)
    ; Gunakan multiplikasi 8-bit
    mul voltage, current    ; Hasil di r1:r0
    
    ; Simpan hasil
    mov power_low, r0
    mov power_high, r1
    
    ; Untuk mendapatkan 1 digit desimal, kita akan menggunakan pendekatan sederhana
    ; Misalnya jika voltage=3 dan current=2, kita ingin power = 6,0
    ; Jika voltage=3 dan current=2.5, kita ingin power = 7,5
    ; Untuk contoh sederhana ambil digit terakhir sebagai desimal
    mov decimal, power_low
    andi decimal, 0x0F      ; Ambil 4 bit terendah sebagai desimal
    
    ; Tampilkan hasil di Serial Monitor
    rcall send_power_to_serial
    
    ; Jeda sebelum pembacaan berikutnya
    rcall delay_1s
    
    rjmp main_loop

; ---- Subrutin untuk mengirim nilai daya ke Serial Monitor ----
send_power_to_serial:
    ; Kirim string "Daya: "
    ldi ZL, LOW(power_message*2)
    ldi ZH, HIGH(power_message*2)
    rcall send_string
    
    ; Konversi power_high:power_low menjadi desimal
    ; Untuk contoh sederhana, kita hanya tampilkan nilai langsung
    ; dan 1 digit desimal
    
    ; Konversi nilai bulat ke ASCII dan kirim
    mov digit, power_high
    rcall convert_and_send_digit
    
    mov digit, power_low
    lsr digit            ; Bagi dengan 16 (geser 4x ke kanan)
    lsr digit
    lsr digit
    lsr digit
    rcall convert_and_send_digit
    
    ; Kirim tanda koma
    ldi temp, '.'
    rcall send_char
    
    ; Kirim digit desimal
    mov digit, decimal
    andi digit, 0x0F     ; Pastikan hanya 1 digit
    rcall convert_and_send_digit
    
    ; Kirim newline
    ldi temp, 13         ; CR
    rcall send_char
    ldi temp, 10         ; LF
    rcall send_char
    
    ret

; Konversi digit menjadi ASCII dan kirim
convert_and_send_digit:
    andi digit, 0x0F     ; Pastikan hanya 1 digit
    ldi temp, '0'
    add temp, digit      ; Konversi ke ASCII
    rcall send_char
    ret

; Kirim string dari program memory
send_string:
    lpm temp, Z+         ; Load byte dari program memory
    tst temp
    breq send_string_end ; Jika null terminator, selesai
    rcall send_char      ; Kirim karakter
    rjmp send_string     ; Loop hingga semua terkirim
send_string_end:
    ret

; Kirim satu karakter ke Serial Monitor
send_char:
wait_tx_ready:
    lds r23, UCSR0A
    sbrs r23, UDRE0      ; Tunggu buffer TX kosong
    rjmp wait_tx_ready
    sts UDR0, temp       ; Kirim karakter
    ret

; Delay ~100ms
delay_100ms:
    ldi r24, 100
delay_1ms_loop:
    ; Delay ~1ms (dengan asumsi 16MHz)
    ldi r22, 200
delay_inner_loop1:
    ldi r23, 40
delay_inner_loop2:
    dec r23
    brne delay_inner_loop2
    dec r22
    brne delay_inner_loop1
    dec r24
    brne delay_1ms_loop
    ret

; Delay ~1s
delay_1s:
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    ret

; String konstan
power_message:
    .db "Daya: ", 0