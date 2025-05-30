; Slave
#define __SFR_OFFSET 0x00
#include "avr/io.h"
.global main
.equ MISO, 4
.equ STATUS_PIN, 7          ; PD7 untuk status flag ke master

main:
    LDI R17, 0xFF
    LDI R17, (1<<PD2)|(1<<PD3)
    OUT DDRD, R17           ; PD2 (LED), PD3 (Buzzer) output
    SBI DDRD, STATUS_PIN    ; PD7 sebagai output
    CBI PORTD, STATUS_PIN   ; Status awal LOW

    CLR R24
    STS UCSR0A, R24
    STS UBRR0H, R24
    LDI R24, 103
    STS UBRR0L, R24
    LDI R24, (1<<RXEN0)|(1<<TXEN0)
    STS UCSR0B, R24
    LDI R24, (1<<UCSZ00)|(1<<UCSZ01)
    STS UCSR0C, R24

SPI_Slave:
    LDI R16, (1<<DDB4) ; MISO sebagai output
    OUT DDRB, R16
    LDI R16, (1<<SPE) ; Enable SPI
    OUT SPCR, R16

looping:
read_sensor:
    RCALL DHT11_sensor
    MOV R18, R25      ; humidity buffer
    MOV R19, R26      ; temp buffer
    SBI PORTD, STATUS_PIN ; Status HIGH: data siap

    ; Layani permintaan SPI: humidity
wait_spi1:
    IN R17, SPSR
    SBRS R17, SPIF
    RJMP wait_spi1
    IN R16, SPDR
    CPI R16, 0x01
    BRNE wait_spi1
    OUT SPDR, R18

    ; Layani permintaan SPI: temp
wait_spi2:
    IN R17, SPSR
    SBRS R17, SPIF
    RJMP wait_spi2
    IN R16, SPDR
    CPI R16, 0x02
    BRNE wait_spi2
    OUT SPDR, R19

    CBI PORTD, STATUS_PIN
    RCALL print_reading
    RJMP looping

DHT11_sensor:
    RCALL delay_sec
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
    RET

print_reading:
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
    ;R26 = temperature
    ;R25 = humidity

    RET

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

uart_transmit:
    LDS R17, UCSR0A
    SBRS R17, UDRE0
    RJMP uart_transmit
    STS UDR0, R24
    RET

print_string:
    LPM R24, Z+
    TST R24
    BREQ print_string_end
    RCALL uart_transmit
    RJMP print_string
print_string_end:
    RET

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

.section .progmem
label_humi:  .asciz "Humidity: "
label_temp:  .asciz "Temp: "
label_c:     .asciz " C\r\n"