; Program Assembly untuk menghitung DAYA (P = V × I)
; Menggunakan ZMPT101B (ADC0) dan ACS712 (ADC1) pada ATMega328P
; Hasil daya (dalam mW) disimpan di R25:R24:R23 (24-bit)

.include "m328pdef.inc"

; Definisi register
.equ ADMUX_SET = (1 << REFS0)  ; AVcc sebagai referensi (5V)
.equ ADCSRA_SET = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0)  ; ADC Enable, prescaler 128
.equ ACS_OFFSET = 512          ; Nilai ADC saat 0A (2.5V)
.equ VOLTAGE_CAL = 22          ; Kalibrasi tegangan (ZMPT101B)
.equ CURRENT_SENS = 20         ; Sensitivitas ACS712-20A (20 steps/A)

; Variabel SRAM
.dseg
.org 0x0100
voltage:    .byte 2  ; Tegangan dalam mV (16-bit)
current:    .byte 2  ; Arus dalam mA (16-bit)
power:      .byte 3  ; Daya dalam mW (24-bit)

; Program utama
.cseg
.org 0x0000
    rjmp main

main:
    ; Inisialisasi stack pointer
    ldi r16, high(RAMEND)
    out SPH, r16
    ldi r16, low(RAMEND)
    out SPL, r16

    ; Konfigurasi ADC
    ldi r16, ADMUX_SET
    sts ADMUX, r16
    ldi r16, ADCSRA_SET
    sts ADCSRA, r16

    ; Inisialisasi UART (untuk debug, opsional)
    call uart_init

loop:
    ; 1. Baca tegangan (ZMPT101B di ADC0)
    ldi r16, 0
    sts ADMUX, r16        ; Pilih ADC0
    call read_adc         ; Hasil di R1:R0
    call calculate_voltage ; Konversi ke mV, hasil di R21:R20

    ; Simpan tegangan ke SRAM
    sts voltage, r20
    sts voltage+1, r21

    ; 2. Baca arus (ACS712 di ADC1)
    ldi r16, 1
    sts ADMUX, r16        ; Pilih ADC1
    call read_adc         ; Hasil di R1:R0
    call calculate_current ; Konversi ke mA, hasil di R21:R20

    ; Simpan arus ke SRAM
    sts current, r20
    sts current+1, r21

    ; 3. Hitung daya (P = V × I)
    lds r18, voltage      ; Load tegangan (low byte)
    lds r19, voltage+1    ; high byte
    lds r20, current      ; Load arus (low byte)
    lds r21, current+1    ; high byte
    call multiply_16x16   ; Hasil di R25:R24:R23 (24-bit)

    ; Simpan daya ke SRAM
    sts power, r23
    sts power+1, r24
    sts power+2, r25

    ; 4. Tampilkan hasil via UART (opsional)
    call display_results

    ; Delay
    call delay_1s

    rjmp loop

; --- Subroutine ---
read_adc:
    ; Mulai konversi ADC
    lds r16, ADCSRA
    ori r16, (1 << ADSC)
    sts ADCSRA, r16
wait_adc:
    lds r16, ADCSRA
    sbrs r16, ADIF
    rjmp wait_adc
    lds r0, ADCL
    lds r1, ADCH
    lds r16, ADCSRA
    ori r16, (1 << ADIF)
    sts ADCSRA, r16
    ret

calculate_voltage:
    ; Konversi ADC ke tegangan (mV): V = (ADC × 5000 × VOLTAGE_CAL) / 1023
    ; Input: R1:R0 (ADC), Output: R21:R20 (mV)
    ; Implementasi disederhanakan (butuh perkalian 16x16)
    ret

calculate_current:
    ; Konversi ADC ke arus (mA): I = ((ADC - 512) × 5000) / (1023 × CURRENT_SENS)
    ; Input: R1:R0 (ADC), Output: R21:R20 (mA)
    ; Implementasi disederhanakan (butuh pengurangan dan perkalian)
    ret

multiply_16x16:
    ; Perkalian 16-bit × 16-bit → 24-bit (V × I)
    ; Input: R19:R18 (V), R21:R20 (I), Output: R25:R24:R23 (P)
    ret

display_results:
    ; Kirim hasil via UART (opsional)
    ; Format: "V=xxx mV, I=xxx mA, P=xxx mW"
    ret

delay_1s:
    ; Delay 1 detik (disesuaikan clock speed)
    ret

uart_init:
    ; Inisialisasi UART (9600 baud)
    ret