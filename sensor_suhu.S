#define __SFR_OFFSET 0x00
#include "avr/io.h"
.global main

;===============================================================
main:
    LDI R17, 0xFF
    OUT DDRC, R17           ; PORTC sebagai output (opsional)
    LDI R17, (1<<PD2)|(1<<PD3)
    OUT DDRD, R17           ; PD2 (LED), PD3 (Buzzer) output

    CLR R24
    STS UCSR0A, R24
    STS UBRR0H, R24
    LDI R24, 103
    STS UBRR0L, R24
    LDI R24, (1<<RXEN0)|(1<<TXEN0)
    STS UCSR0B, R24
    LDI R24, (1<<UCSZ00)|(1<<UCSZ01)
    STS UCSR0C, R24

    RJMP DHT11_sensor

I2C_slave:
    LDI   R21, 0xFF
    OUT   DDRD, R21         ;port D is o/p
    CBI   DDRC, 3           ;pin PC3 is i/p

agn1:RCALL I2C_init          ;initialize TWI module
    RCALL I2C_listen        ;listen to bus to be addressed
    LDI   R27, R25
    RCALL I2C_write          ;read data byte
    LDi   R27, R26
    RCALL I2C_write          ;read data byte
    OUT   PORTD, R27        ;and o/p to port D

l1: SBIS  PINC, 3
    RJMP  l1                ;wait for "listen" button press

    LDI   R26, 0
    OUT   PORTD, R26        ;clear port D
    RJMP  DHT11_sensor               ;& go back & listen to bus

I2C_init:
    LDI   R21, 0b10010000
    STS   TWAR, R21         ;store slave address 0b10010000
    LDI   R21, (1<<TWEN)
    STS   TWCR, R21         ;enable TWI
    LDI   R21, (1<<TWINT)|(1<<TWEN)|(1<<TWEA)
    STS   TWCR, R21         ;enable TWI & ACK
    RET

I2C_listen:
    LDS   R21, TWCR 
    SBRS  R21, TWINT
    RJMP  I2C_listen        ;wait for slave to be addressed
    RET

I2C_write:
    STS   TWDR, R27       ;copy SLA+W into data register
    LDI   R21, (1<<TWINT)|(1<<TWEN)
    STS   TWCR, R21       ;transmit SLA+W
    ;----------------------------------------------------------
wt2:LDS   R21, TWCR
    SBRS  R21, TWINT
    RJMP  wt2             ;wait for end of transmission
    ;----------------------------------------------------------
    RET


DHT11_sensor:
agn:
    RCALL delay_2s

    ; Start signal ke DHT11
    SBI DDRB, 1
    CBI PORTB, 1
    RCALL delay_20ms
    SBI PORTB, 1

    ; Tunggu respon DHT11
    CBI DDRB, 1
w1: SBIC PINB, 1
    RJMP w1
w2: SBIS PINB, 1
    RJMP w2
w3: SBIC PINB, 1
    RJMP w3

    ; Baca data DHT11
    RCALL DHT11_reading
    MOV R25, R24         ; humidity (integer)

    RCALL DHT11_reading  ; humidity decimal (abaikan)
    RCALL DHT11_reading
    MOV R26, R24         ; temperature (integer)

    RCALL DHT11_reading  ; temperature decimal (abaikan)
    RCALL DHT11_reading  ; checksum (abaikan)

    ; UART: print humidity
    LDI ZL, lo8(label_humi)
    LDI ZH, hi8(label_humi)
    RCALL print_string
    MOV R24, R25
    RCALL print_decimal
    LDI R24, '%'
    RCALL uart_transmit
    LDI R24, 0x0D
    RCALL uart_transmit
    LDI R24, 0x0A
    RCALL uart_transmit

    ; UART: print temperature
    LDI ZL, lo8(label_temp)
    LDI ZH, hi8(label_temp)
    RCALL print_string
    MOV R24, R26
    RCALL print_decimal
    LDI ZL, lo8(label_c)
    LDI ZH, hi8(label_c)
    RCALL print_string
    //R26 = temperature
    //R25 = humidity
    RJMP agn1

;===============================================================
; Subrutin Baca 8-bit DHT11 ke R24
DHT11_reading:
    LDI R16, 8
    CLR R24
w4: SBIS PINB, 1
    RJMP w4
    RCALL delay_timer0
    SBIS PINB, 1
    RJMP skp
    SEC
    ROL R24
    RJMP w5
skp:LSL R24
w5: SBIC PINB, 1
    RJMP w5
    DEC R16
    BRNE w4
    RET

;===============================================================
; UART kirim satu karakter di R24
uart_transmit:
    LDS R17, UCSR0A
    SBRS R17, UDRE0
    RJMP uart_transmit
    STS UDR0, R24
    RET

; Print string dari Z
print_string:
    LPM R24, Z+
    TST R24
    BREQ print_string_end
    RCALL uart_transmit
    RJMP print_string
print_string_end:
    RET

; Cetak bilangan 0-99
print_decimal:
    CLR R18
    CLR R21
tens_loop:
    CPI R24, 10
    BRLO tens_done
    SUBI R24, 10
    INC R21
    RJMP tens_loop
tens_done:
    TST R21
    BREQ print_ones
print_tens:
    MOV R18, R21
    MOV R22, R24
    MOV R24, R21
    LDI R21, '0'
    ADD R24, R21
    RCALL uart_transmit
    MOV R24, R22
print_ones:
    LDI R21, '0'
    ADD R24, R21
    RCALL uart_transmit
    RET

;===============================================================
; Delay Routines
delay_20ms:
    LDI R21, 255
l3: LDI R22, 210
l4: LDI R23, 2
l5: DEC R23
    BRNE l5
    DEC R22
    BRNE l4
    DEC R21
    BRNE l3
    RET

delay_2s:
    LDI R21, 255
l6: LDI R22, 255
l7: LDI R23, 164
l8: DEC R23
    BRNE l8
    DEC R22
    BRNE l7
    DEC R21
    BRNE l6
    RET

delay_sec:
    LDI R20, 255
s1: LDI R21, 255
s2: LDI R22, 80
s3: DEC R22
    BRNE s3
    DEC R21
    BRNE s2
    DEC R20
    BRNE s1
    RET

delay_timer0:
    CLR R20
    OUT TCNT0, R20
    LDI R20, 100
    OUT OCR0A, R20
    LDI R20, 0b00001010
    OUT TCCR0B, R20
l2: IN R20, TIFR0
    SBRS R20, OCF0A
    RJMP l2
    CLR R20
    OUT TCCR0B, R20
    LDI R20, (1<<OCF0A)
    OUT TIFR0, R20
    RET

;===============================================================
; String untuk UART
.section .progmem
label_humi:  .asciz "Humidity: "
label_temp:  .asciz "Temp: "
label_c:     .asciz " C\r\n"