#define __SFR_OFFSET 0x00
#include "avr/io.h"
.global main

main:
    ; Setup ADC input dan output pin
    SBI   DDRD, 2           ; PD2 sebagai output
    CBI   DDRC, 0           ; PC0 sebagai input (ADC0)

    ; Inisialisasi ADC: AVCC ref, right justified, channel 0
    LDI   R20, 0x40
    STS   ADMUX, R20
    ; Enable ADC, CLK/128
    LDI   R20, 0x87
    STS   ADCSRA, R20

init_serial:
    CLR   R24
    STS   UCSR0A, R24
    STS   UBRR0H, R24
    LDI   R24, 103
    STS   UBRR0L, R24       ; Baudrate 9600
    LDI   R24, 1<<RXEN0 | 1<<TXEN0
    STS   UCSR0B, R24
    LDI   R24, 1<<UCSZ00 | 1<<UCSZ01
    STS   UCSR0C, R24

print_ADC:
    ; Mulai konversi ADC
    LDI   R20, 0xC7
    STS   ADCSRA, R20

wait_ADC:
    LDS   R21, ADCSRA
    SBRS  R21, 4
    RJMP  wait_ADC
    LDI   R17, 0xD7
    STS   ADCSRA, R17

    ; Ambil hasil ADC 10-bit
    LDS   R16, ADCL
    LDS   R25, ADCH

    ; Konversi ADC ke suhu (25-40 derajat)
    ; Formula: Temp = 25 + (ADC * 15 / 1023)
    
    ; Salin nilai ADC ke R17:R16
    MOV   R17, R25
    
    ; Kalikan dengan 15 (untuk range 15 derajat)
    MOV   R25, R17      ; Salin high byte ke R25
    MOV   R24, R16      ; Salin low byte ke R24
    
    LDI   R20, 15       ; Faktor pengali = 15
    MUL   R24, R20      ; Kalikan low byte dengan 15
    MOVW  R22, R0       ; Hasil ke R23:R22
    
    MUL   R25, R20      ; Kalikan high byte dengan 15
    ADD   R23, R0       ; Tambahkan ke hasil
    
    ; Bagi dengan 1023 (pembagian 16-bit yang disederhanakan)
    ; Untuk keperluan praktis, kita bagi dengan 1024 (shift right 10x)
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    LSR   R23
    ROR   R22
    
    ; Tambahkan offset suhu minimum (25 derajat)
    LDI   R23, 0        ; Clear R23 (high byte)
    LDI   R20, 25       ; Tambahkan 25
    ADD   R22, R20      ; R22 sekarang berisi nilai suhu (25-40)
    
    ; Print string "Temp: "
    LDI   ZL, lo8(temp_str)
    LDI   ZH, hi8(temp_str)
    RCALL print_string
    
    ; Mencetak nilai suhu
    MOV   R24, R22      ; Pindahkan suhu ke R24
    RCALL print_decimal
    
    ; Cetak string " C"
    LDI   ZL, lo8(degree_str)
    LDI   ZH, hi8(degree_str)
    RCALL print_string
    
    ; Print newline
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit
    
    RCALL delay_sec
    RJMP  print_ADC

; -----------------------------------------------
; Fungsi untuk mencetak string
print_string:
    LD    R24, Z+
    TST   R24
    BREQ  print_string_end
    RCALL uart_transmit
    RJMP  print_string
print_string_end:
    RET

; -----------------------------------------------
; Fungsi untuk mengirim byte melalui UART
uart_transmit:
    LDS   R17, UCSR0A
    SBRS  R17, UDRE0
    RJMP  uart_transmit
    STS   UDR0, R24
    RET

; -----------------------------------------------
; Fungsi untuk mencetak nilai desimal
; Input: R24 = nilai (0-255)
print_decimal:
    CLR   R18       ; Digit counter
    
    ; Cek apakah nilai >= 100
    LDI   R19, 100  ; Pembagi
    MOV   R20, R24  ; Salin nilai asli
    
    ; Hitung digit ratusan
    CLR   R21       ; Reset hasil
hundreds_loop:
    CPI   R20, 100
    BRLO  hundreds_done
    SUBI  R20, 100
    INC   R21
    RJMP  hundreds_loop
hundreds_done:
    
    ; Jika digit ratusan tidak nol, cetak
    TST   R21
    BREQ  skip_hundreds
    MOV   R24, R21
    LDI   R21, '0'
    ADD   R24, R21
    RCALL uart_transmit
skip_hundreds:
    
    ; Hitung digit puluhan
    MOV   R24, R20  ; Sisa dari pembagian sebelumnya
    LDI   R19, 10   ; Pembagi
    CLR   R21       ; Reset hasil
tens_loop:
    CPI   R24, 10
    BRLO  tens_done
    SUBI  R24, 10
    INC   R21
    RJMP  tens_loop
tens_done:
    
    ; Jika digit ratusan nol dan puluhan nol, skip
    ; Jika tidak, cetak digit puluhan
    TST   R18
    BRNE  print_tens
    TST   R21
    BREQ  skip_tens
print_tens:
    MOV   R18, R21  ; Tandai bahwa setidaknya satu digit telah dicetak
    MOV   R22, R24  ; Simpan sisa untuk digit satuan
    MOV   R24, R21
    LDI   R21, '0'
    ADD   R24, R21
    RCALL uart_transmit
    MOV   R24, R22  ; Kembalikan sisa
    RJMP  print_ones
skip_tens:
    MOV   R18, R21  ; Jangan tandai sebagai telah dicetak
    
print_ones:
    ; Cetak digit satuan
    LDI   R21, '0'
    ADD   R24, R21
    RCALL uart_transmit
    RET

; -----------------------------------------------
; Fungsi delay ~1 detik
delay_sec:
    LDI   R20, 255
l6: LDI   R21, 255
l7: LDI   R22, 80
l8: DEC   R22
    BRNE  l8
    DEC   R21
    BRNE  l7
    DEC   R20
    BRNE  l6
    RET

; -----------------------------------------------
; Data string
.section .rodata
temp_str:     .asciz "Temp: "
degree_str:   .asciz " C"