#define __SFR_OFFSET 0x00
#include "avr/io.h"
.global main

main:
    CBI   DDRC, 0           ; PC0 sebagai input (ADC0)
    SBI   DDRD, 2           ; LED
    SBI   DDRD, 3           ; Buzzer
    LDI   R20, 0x40         ; AVCC sebagai reference, right justified, ADC0
    STS   ADMUX, R20

    LDI   R20, 0x87         ; ADC enable, prescaler 128
    STS   ADCSRA, R20

init_serial:
    CLR   R24
    STS   UCSR0A, R24
    STS   UBRR0H, R24
    LDI   R24, 103
    STS   UBRR0L, R24       ; 9600
    LDI   R24, 1<<RXEN0 | 1<<TXEN0
    STS   UCSR0B, R24
    LDI   R24, 1<<UCSZ00 | 1<<UCSZ01
    STS   UCSR0C, R24

print_ADC:
    LDI   R20, 0xC7     ; Mulai konversi ADC
    STS   ADCSRA, R20
wait_ADC:
    LDS   R21, ADCSRA
    SBRS  R21, 4   
    RJMP  wait_ADC
    LDI   R17, 0xD7
    STS   ADCSRA, R17

    LDS   R16, ADCL
    LDS   R17, ADCH

    ; Formula: Temp = 25 + (ADC * 15 / 1023)

    MOV   R25, R17      ; Salin high byte ke R25
    MOV   R24, R16      ; Salin low byte ke R24
    
    LDI   R20, 16       ; Faktor pengali = 16
    MUL   R24, R20      ; Kalikan low byte dengan 15
    MOVW  R22, R0       ; Hasil ke R23:R22
    
    MUL   R25, R20      ; Kalikan high byte dengan 15
    ADD   R23, R0       ; Tambahkan ke hasil
    
    LDI  R20, 10

divide_loop:
    LSR     23
    ROR     22
    SUBI    R20, 1
    BREQ    divide_done
    RJMP    divide_loop

divide_done:
    CLR     R23        ; Clear R23 (high byte)
    LDI     R20, 25       ; Tambahkan 25
    ADD     R22, R20      ; R22 sekarang berisi nilai suhu (25-40)
    
    ; Print string "Temp: "
    LDI     ZL, lo8(temp)
    LDI     ZH, hi8(temp)
    RCALL   print_string
    
    ; Mencetak nilai suhu
    MOV   R24, R22      ; Pindahkan suhu ke R24
    RCALL print_decimal
    
    ; Cetak string " C"
    LDI   ZL, lo8(degree)
    LDI   ZH, hi8(degree)
    RCALL print_string
    
    ; Print newline
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit

    ; buat ketika nilai suhu diantara diatas 33, lampu led akan berkedip namun buzzer tidak berbunyi
    ; ketika suhu diatas 36, led akan menyala dan buzzer berbunyi

    RCALL delay_sec
    RJMP  print_ADC

print_string:
    LPM   R24, Z+
    TST   R24
    BREQ  print_string_end
    RCALL uart_transmit
    RJMP  print_string
print_string_end:
    RET

uart_transmit:
    LDS   R17, UCSR0A
    SBRS  R17, UDRE0
    RJMP  uart_transmit
    STS   UDR0, R24
    RET

print_decimal:
    CLR   R18       ; Digit counter
    CLR   R21       ; Reset hasil

tens_loop:
    CPI   R24, 10
    BRLO  tens_done
    SUBI  R24, 10
    INC   R21
    RJMP  tens_loop

tens_done:
    TST   R21
    BREQ  print_ones

print_tens:
    MOV   R18, R21  ; Tandai bahwa setidaknya satu digit telah dicetak
    MOV   R22, R24  ; Simpan sisa untuk digit satuan
    MOV   R24, R21
    LDI   R21, '0'
    ADD   R24, R21
    RCALL uart_transmit
    MOV   R24, R22  ; Kembalikan sisa
    RJMP  print_ones
    
print_ones:
    LDI   R21, '0'
    ADD   R24, R21
    RCALL uart_transmit
    RET

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

.section .progmem
temp:     .asciz "Temp: "
degree:   .asciz " C"