; Master with OLED Display Integration
#define __SFR_OFFSET 0x00
#include "avr/io.h"

;=====================================================================
; I2C and SSD1306 definitions for OLED
;=====================================================================
#define SDA_PIN 4       ; PC4 (A4) - Connect OLED SDA here
#define SCL_PIN 5       ; PC5 (A5) - Connect OLED SCL here
#define SSD1306_ADDR 0x3C
#define COMMAND_MODE 0x00
#define DATA_MODE 0x40

;=====================================================================
; Original master code constants for SPI
;=====================================================================
.equ SCK, 5            ; PB5 - Connect to Slave SCK
.equ MISO, 4           ; PB4 - Connect to Slave MISO
.equ MOSI, 3           ; PB3 - Connect to Slave MOSI
.equ SS, 2             ; PB2 - Connect to Slave SS
.equ STATUS_PIN, 7     ; PD7 - Connect to Slave status pin

.global main

main:
    ;=====================================================================
    ; Master Hardware Initialization
    ;=====================================================================
    CBI   DDRC, 0           ; PC0 as input (ADC0 for potentiometer)
    SBI   DDRD, 2           ; PD2 as output for LED
    SBI   DDRD, 3           ; PD3 as output for buzzer
    CBI   PORTD, 2          ; LED OFF initially
    CBI   DDRD, STATUS_PIN  ; PD7 as input (status from slave)
    
    ;=====================================================================
    ; Initialize OLED display (I2C setup)
    ;=====================================================================
    RCALL I2C_init          ; Initialize I2C bus for OLED
    RCALL SSD1306_init      ; Initialize OLED display
    RCALL clear_screen      ; Clear OLED screen
    RCALL delay_long        ; Add delay after clearing screen
    
    ; Display static weather station title
    RCALL display_static_text
    
    ;=====================================================================
    ; ADC setup for potentiometer reading (threshold control)
    ;=====================================================================
    LDI   R20, 0x40         ; AVCC as reference, right justified, ADC0
    STS   ADMUX, R20
    LDI   R20, 0x87         ; ADC enable, prescaler 128
    STS   ADCSRA, R20

    ; Initialize buffer registers with zero values
    CLR   R28               ; Temperature buffer register
    CLR   R29               ; Humidity buffer register

    ;=====================================================================
    ; UART initialization (for debugging)
    ;=====================================================================
    CLR   R24
    STS   UCSR0A, R24
    STS   UBRR0H, R24
    LDI   R24, 103
    STS   UBRR0L, R24       ; 9600 baud
    LDI   R24, 1<<RXEN0 | 1<<TXEN0
    STS   UCSR0B, R24
    LDI   R24, 1<<UCSZ00 | 1<<UCSZ01
    STS   UCSR0C, R24

    ;=====================================================================
    ; SPI Master initialization
    ;=====================================================================
    LDI R16, (1<<DDB2)|(1<<DDB3)|(1<<DDB5) ; MOSI, SCK, SS as outputs
    OUT DDRB, R16
    LDI R16, (1<<SPE)|(1<<MSTR)|(1<<SPR0) ; Enable SPI, Master, prescaler 16
    OUT SPCR, R16
    SBI DDRD, 4
    CBI PORTD, 4           ; Status LED OFF

;=====================================================================
; Main program loop
;=====================================================================
looping:
    ;=====================================================================
    ; Wait for slave to have data ready (HIGH status on PD7)
    ;=====================================================================
wait_slave_ready:
    SBIS PIND, STATUS_PIN   ; Check status flag on PD7 (must be HIGH)
    RJMP wait_slave_ready

    ;=====================================================================
    ; SPI: Request Humidity data from slave
    ;=====================================================================
    LDI R20, 0x01           ; Command code for humidity
    OUT SPDR, R20           ; Send command
wait_spi_dummy_humi:
    IN R22, SPSR
    SBRS R22, SPIF
    RJMP wait_spi_dummy_humi
    IN R30, SPDR            ; Discard first byte (garbage)

    LDI R20, 0x01           ; Command code for humidity again
    OUT SPDR, R20           ; Send command
wait_spi_humi:
    IN R22, SPSR
    SBRS R22, SPIF
    RJMP wait_spi_humi
    IN R27, SPDR            ; Store HUMIDITY value

    ;=====================================================================
    ; SPI: Request Temperature data from slave
    ;=====================================================================
    LDI R21, 0x02           ; Command code for temperature
    OUT SPDR, R21           ; Send command
wait_spi_dummy_temp:
    IN R23, SPSR
    SBRS R23, SPIF
    RJMP wait_spi_dummy_temp
    IN R31, SPDR            ; Discard first byte

    LDI R21, 0x02           ; Command code for temperature again
    OUT SPDR, R21           ; Send command
wait_spi_temp:
    IN R23, SPSR
    SBRS R23, SPIF
    RJMP wait_spi_temp
    IN R26, SPDR            ; Store TEMPERATURE value

    ;=====================================================================
    ; Wait for slave status to go LOW (indicating data transmission complete)
    ;=====================================================================
wait_flag_low:
    SBIC PIND, STATUS_PIN   ; Wait until status is LOW
    RJMP wait_flag_low

    ;=====================================================================
    ; Validate and update buffers (only update if non-zero values received)
    ;=====================================================================
    ; Buffer for humidity: R29
    CPI R27, 0              ; Check if received humidity value is zero
    BREQ humi_skip_update
    MOV R29, R27            ; Update buffer with new humidity value
humi_skip_update:

    ; Buffer for temperature: R28
    CPI R26, 0              ; Check if received temperature value is zero
    BREQ temp_skip_update
    MOV R28, R26            ; Update buffer with new temperature value
temp_skip_update:

    ;=====================================================================
    ; IMPORTANT: Save sensor values before OLED display update
    ;=====================================================================
    PUSH  R28               ; Save temperature value
    PUSH  R29               ; Save humidity value
    
    ; Copy saved values for OLED display functions
    MOV   R25, R28          ; Copy temperature to R25 (used by OLED functions)
    MOV   R26, R29          ; Copy humidity to R26 (used by OLED functions)
    
    ; Update OLED display with current values
    RCALL display_temperature
    RCALL display_humidity
    
    ; Restore original values after OLED display update
    POP   R29               ; Restore humidity value
    POP   R28               ; Restore temperature value

    ;=====================================================================
    ; UART output (for debugging or serial monitor display)
    ;=====================================================================
    ; Print Humidity
    LDI   ZL, lo8(cur_humi)
    LDI   ZH, hi8(cur_humi)
    RCALL print_string
    MOV   R24, R29          ; Use humidity buffer value
    RCALL print_decimal
    LDI   ZL, lo8(percent)
    LDI   ZH, hi8(percent)
    RCALL print_string
    LDI   R24, 0x0D         ; Carriage return
    RCALL uart_transmit
    LDI   R24, 0x0A         ; Line feed
    RCALL uart_transmit

    ; Print Temperature
    LDI   ZL, lo8(cur_temp)
    LDI   ZH, hi8(cur_temp)
    RCALL print_string
    MOV   R24, R28          ; Use temperature buffer value
    RCALL print_decimal
    LDI   ZL, lo8(degree)
    LDI   ZH, hi8(degree)
    RCALL print_string
    LDI   R24, 0x0D         ; Carriage return
    RCALL uart_transmit
    LDI   R24, 0x0A         ; Line feed
    RCALL uart_transmit

    ;=====================================================================
    ; Read ADC for temperature threshold
    ;=====================================================================
    RCALL print_ADC

;=====================================================================
; Read ADC and handle temperature threshold logic
;=====================================================================
print_ADC:
    LDI   R20, 0xC7         ; Start ADC conversion
    STS   ADCSRA, R20
wait_ADC:
    LDS   R21, ADCSRA       ; Wait for ADC conversion to complete
    SBRS  R21, 4   
    RJMP  wait_ADC
    LDI   R17, 0xD7
    STS   ADCSRA, R17

    LDS   R16, ADCL         ; Read ADC value
    LDS   R17, ADCH

    ; Formula: Temp = 25 + (ADC * 15 / 1023)
    MOV   R25, R17          ; Copy high byte to R25
    MOV   R24, R16          ; Copy low byte to R24

    LDI   R20, 16           ; Multiplier = 16
    MUL   R24, R20          ; Multiply low byte by 15
    MOVW  R22, R0           ; Result to R23:R22

    MUL   R25, R20          ; Multiply high byte by 15
    ADD   R23, R0           ; Add to result

    LDI  R20, 10            ; Divide by 2^10 (1024)

divide_loop:
    LSR   R23
    ROR   R22
    SUBI  R20, 1
    BREQ  divide_done
    RJMP  divide_loop

divide_done:
    CLR   R23               ; Clear R23 (high byte)
    LDI   R20, 25           ; Add 25
    ADD   R22, R20          ; R22 now contains threshold temperature value (25-40)

    ; Print "Threshold Temp: " string
    LDI   ZL, lo8(temp)
    LDI   ZH, hi8(temp)
    RCALL print_string
    ; Print temperature value
    MOV   R24, R22          ; Move temperature to R24
    MOV   R25, R22          ; Save a copy in R25 for threshold checks
    RCALL print_decimal
    ; Print " C" string
    LDI   ZL, lo8(degree)
    LDI   ZH, hi8(degree)
    RCALL print_string

    ; Print newline
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit

    ;=====================================================================
    ; Update OLED display with threshold value
    ;=====================================================================
    ; Save registers before calling OLED functions
    PUSH  R28
    PUSH  R29
    PUSH  R25
    PUSH  R26
    
    ; Display threshold on OLED
    MOV   R25, R22          ; Copy threshold to R25 (used by display function)
    LDI   R20, 7            ; Page 7 (bottom row)
    LDI   R21, 32           ; Column 32
    RCALL set_cursor
    
    ; Start I2C communication for threshold text
    RCALL I2C_start
    LDI   R16, (SSD1306_ADDR<<1)
    RCALL I2C_write
    LDI   R16, DATA_MODE
    RCALL I2C_write
    
    ; Display "THRESHOLD: " text
    LDI   R24, 'T'
    RCALL process_char
    LDI   R24, 'H'
    RCALL process_char
    LDI   R24, 'R'
    RCALL process_char
    LDI   R24, ':'
    RCALL process_char
    LDI   R24, ' '
    RCALL process_char
    
    ; Display threshold value
    MOV   R24, R25         ; Copy threshold to R24
    
    ; Divide by 10 to get tens digit
    LDI   R18, 10
    RCALL divide_display   ; R24 = quotient (tens), R19 = remainder (ones)
    
    ; Display tens digit
    SUBI  R24, -'0'        ; Convert to ASCII ('0' = 48)
    RCALL process_char     ; Display tens digit
    
    ; Display ones digit
    MOV   R24, R19         ; Move remainder to R24
    SUBI  R24, -'0'        ; Convert to ASCII
    RCALL process_char     ; Display ones digit
    
    ; Display space and C
    LDI   R24, ' '
    RCALL process_char
    LDI   R24, 'C'
    RCALL process_char
    
    ; End I2C transaction
    RCALL I2C_stop
    
    ; Restore registers
    POP   R26
    POP   R25
    POP   R29
    POP   R28

    ;=====================================================================
    ; Check temperature against threshold and control alarm
    ;=====================================================================
status:
    ; === Step 1: If temp buffer (R28) >= threshold (R25), alarm ON ===
    CP    R28, R25
    BRSH  led_on            ; If temp >= threshold, alarm ON

    ; === Step 2: If temp buffer >= threshold-5, LED blink ===
    MOV   R30, R25          ; Copy threshold to R30
    SUBI  R30, 5            ; R30 = threshold - 5
    CP    R28, R30
    BRSH  led_blink         ; If temp >= threshold-5, LED blink

    ; === Step 3: If temp < threshold-5, all OFF ===
    RJMP  led_off

;=====================================================================
; State Subroutines for LED/Buzzer control
;=====================================================================
led_on:
    SBI   PORTD, 2          ; LED ON
    SBI   PORTD, 3          ; BUZZER ON
    RJMP  skip_led

led_blink:
    SBI   PORTD, 2          ; LED ON
    CBI   PORTD, 3          ; BUZZER OFF
    RCALL delay_sec
    CBI   PORTD, 2          ; LED OFF
    RCALL delay_sec
    RJMP  skip_led

led_off:
    CBI   PORTD, 2          ; LED OFF
    CBI   PORTD, 3          ; BUZZER OFF
    RJMP  skip_led

skip_led:
    RCALL delay_sec
    RJMP  looping

;=====================================================================
; Original Master UART and utility functions
;=====================================================================
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
    CLR   R18
    CLR   R21

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
    MOV   R18, R21
    MOV   R22, R24
    MOV   R24, R21
    LDI   R21, '0'
    ADD   R24, R21
    RCALL uart_transmit
    MOV   R24, R22
    RJMP  print_ones

print_ones:
    LDI   R21, '0'
    ADD   R24, R21
    RCALL uart_transmit
    RET

;=====================================================================
; Add all the remaining code from paste-3.txt here
;=====================================================================
; I2C Functions
I2C_init:
    ; Set I2C pins as outputs initially
    SBI   DDRC, SDA_PIN    ; SDA as output
    SBI   DDRC, SCL_PIN    ; SCL as output
    ; Set both lines high (idle state)
    SBI   PORTC, SDA_PIN
    SBI   PORTC, SCL_PIN
    RCALL delay_ms         ; Stabilize
    RET

I2C_start:
    SBI   PORTC, SDA_PIN   ; Ensure SDA is high
    SBI   PORTC, SCL_PIN   ; Ensure SCL is high
    RCALL delay_us
    CBI   PORTC, SDA_PIN   ; SDA goes low while SCL is high (START)
    RCALL delay_us
    CBI   PORTC, SCL_PIN   ; SCL low
    RET

I2C_stop:
    CBI   PORTC, SDA_PIN   ; SDA low
    RCALL delay_us
    SBI   PORTC, SCL_PIN   ; SCL high
    RCALL delay_us
    SBI   PORTC, SDA_PIN   ; SDA high while SCL high (STOP)
    RCALL delay_ms         ; Extra delay after stop
    RET

I2C_write:
    ; Byte to send is in R16
    LDI   R17, 8           ; 8 bits to send
send_bit:
    ROL   R16              ; Move MSB to carry
    BRCS  send_one
    CBI   PORTC, SDA_PIN   ; Send 0
    RJMP  clock_pulse
send_one:
    SBI   PORTC, SDA_PIN   ; Send 1
clock_pulse:
    RCALL delay_us
    SBI   PORTC, SCL_PIN   ; SCL high
    RCALL delay_us
    CBI   PORTC, SCL_PIN   ; SCL low
    RCALL delay_us
    DEC   R17
    BRNE  send_bit
    
    ; Check ACK
    CBI   DDRC, SDA_PIN    ; SDA as input to read ACK
    SBI   PORTC, SDA_PIN   ; Enable pull-up
    RCALL delay_us
    SBI   PORTC, SCL_PIN   ; SCL high
    RCALL delay_us
    IN    R17, PINC        ; Read ACK bit
    CBI   PORTC, SCL_PIN   ; SCL low
    SBI   DDRC, SDA_PIN    ; SDA back to output
    RCALL delay_us
    
    ANDI  R17, 0x10        ; Mask SDA pin (bit 4)
    ; If R17 is 0, ACK received
    RET

;=====================================================================
; SSD1306 Display Functions
;=====================================================================
SSD1306_init:
    RCALL I2C_start
    
    ; Send device address
    LDI   R16, (SSD1306_ADDR<<1)  ; SSD1306 address with write bit
    RCALL I2C_write
    
    ; Send command mode byte
    LDI   R16, COMMAND_MODE
    RCALL I2C_write
    
    ; Send initialization commands
    LDI   R16, 0xAE        ; Display off
    RCALL I2C_write
    
    RCALL delay_ms         ; Add extra delay between commands
    
    LDI   R16, 0xD5        ; Set display clock
    RCALL I2C_write
    LDI   R16, 0x80        ; Recommended value
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xA8        ; Set multiplex
    RCALL I2C_write
    LDI   R16, 0x3F        ; 64 rows
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xD3        ; Set display offset
    RCALL I2C_write
    LDI   R16, 0x00        ; No offset
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0x40        ; Set start line to 0
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0x8D        ; Charge pump
    RCALL I2C_write
    LDI   R16, 0x14        ; Enable charge pump
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0x20        ; Memory mode
    RCALL I2C_write
    LDI   R16, 0x00        ; Horizontal addressing
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xA1        ; Segment remap
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xC8        ; COM scan direction
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xDA        ; COM pins
    RCALL I2C_write
    LDI   R16, 0x12        ; COM pins configuration
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0x81        ; Set contrast
    RCALL I2C_write
    LDI   R16, 0xFF        ; Maximum contrast value
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xD9        ; Pre-charge period
    RCALL I2C_write
    LDI   R16, 0xF1        ; Pre-charge value
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xDB        ; VCOMH Deselect
    RCALL I2C_write
    LDI   R16, 0x40        ; VCOMH value
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xA4        ; Display RAM
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xA6        ; Normal display (not inverted)
    RCALL I2C_write
    
    RCALL delay_ms
    
    LDI   R16, 0xAF        ; Display on
    RCALL I2C_write
    
    RCALL I2C_stop
    RCALL delay_long       ; Extra long delay after initialization
    RET

;=====================================================================
; Clear OLED screen
;=====================================================================
clear_screen:
    ; Set address range for the entire display
    RCALL I2C_start
    LDI   R16, (SSD1306_ADDR<<1)
    RCALL I2C_write
    LDI   R16, COMMAND_MODE
    RCALL I2C_write
    
    ; Set page address (all pages)
    LDI   R16, 0x22        ; Page address command
    RCALL I2C_write
    LDI   R16, 0           ; Start page 0
    RCALL I2C_write
    LDI   R16, 7           ; End page 7
    RCALL I2C_write
    
    ; Set column address (all columns)
    LDI   R16, 0x21        ; Column address command
    RCALL I2C_write
    LDI   R16, 0           ; Start column 0
    RCALL I2C_write
    LDI   R16, 127         ; End column 127
    RCALL I2C_write
    RCALL I2C_stop
    
    ; Clear all pixels
    RCALL I2C_start
    LDI   R16, (SSD1306_ADDR<<1)
    RCALL I2C_write
    LDI   R16, DATA_MODE
    RCALL I2C_write
    
    ; Fill all 1024 bytes (8 pages × 128 columns) with 0
    LDI   R18, 8           ; 8 pages
page_loop_clear:
    LDI   R19, 128         ; 128 columns per page
col_loop_clear:
    LDI   R16, 0x00        ; All pixels OFF
    RCALL I2C_write
    DEC   R19
    BRNE  col_loop_clear
    DEC   R18
    BRNE  page_loop_clear
    
    RCALL I2C_stop
    RET

;=====================================================================
; Position cursor at specified page and column
;=====================================================================
set_cursor:
    RCALL I2C_start
    LDI   R16, (SSD1306_ADDR<<1)
    RCALL I2C_write
    LDI   R16, COMMAND_MODE
    RCALL I2C_write
    
    ; Set page address
    LDI   R16, 0x22        ; Page address command
    RCALL I2C_write
    MOV   R16, R20         ; Page from R20
    RCALL I2C_write
    MOV   R16, R20         ; Same page for end
    RCALL I2C_write
    
    ; Set column address
    LDI   R16, 0x21        ; Column address command
    RCALL I2C_write
    MOV   R16, R21         ; Column from R21
    RCALL I2C_write
    LDI   R16, 127         ; End at column 127
    RCALL I2C_write
    
    RCALL I2C_stop
    RET

;=====================================================================
; Display static text (title)
;=====================================================================
display_static_text:
    ; Set cursor position for title
    LDI   R20, 1           ; Page 1 (top row)
    LDI   R21, 16          ; Column 16 (centered)
    RCALL set_cursor
    
    ; Display "WEATHER STATION"
    LDI   ZL, lo8(str_title)
    LDI   ZH, hi8(str_title)
    RCALL display_string
    
    RET

;=====================================================================
; Convert temperature to ASCII and display it
;=====================================================================
display_temperature:
    ; Set cursor position for temperature display
    LDI   R20, 3           ; Page 3 (temperature row)
    LDI   R21, 32          ; Column 32 (centered)
    RCALL set_cursor
    
    ; Start I2C communication for the entire string
    RCALL I2C_start
    LDI   R16, (SSD1306_ADDR<<1)
    RCALL I2C_write
    LDI   R16, DATA_MODE
    RCALL I2C_write
    
    ; Display "TEMP: " text
    LDI   R24, 'T'
    RCALL process_char
    LDI   R24, 'E'
    RCALL process_char
    LDI   R24, 'M'
    RCALL process_char
    LDI   R24, 'P'
    RCALL process_char
    LDI   R24, ':'
    RCALL process_char
    LDI   R24, ' '
    RCALL process_char
    
    ; Convert temperature to ASCII digits
    MOV   R24, R25         ; Copy temperature to R24
    
    ; Divide by 10 to get tens digit
    LDI   R18, 10
    RCALL divide_display   ; R24 = quotient (tens), R19 = remainder (ones)
    
    ; Display tens digit
    SUBI  R24, -'0'        ; Convert to ASCII ('0' = 48)
    RCALL process_char     ; Display tens digit
    
    ; Display ones digit
    MOV   R24, R19         ; Move remainder to R24
    SUBI  R24, -'0'        ; Convert to ASCII
    RCALL process_char     ; Display ones digit
    
    ; Display space and C
    LDI   R24, ' '
    RCALL process_char
    LDI   R24, 'C'
    RCALL process_char
    
    ; End I2C transaction
    RCALL I2C_stop
    RET

;=====================================================================
; Convert humidity to ASCII and display it
;=====================================================================
display_humidity:
    ; Set cursor position for humidity display
    LDI   R20, 5           ; Page 5 (humidity row)
    LDI   R21, 32          ; Column 32 (centered)
    RCALL set_cursor
    
    ; Start I2C communication for the entire string
    RCALL I2C_start
    LDI   R16, (SSD1306_ADDR<<1)
    RCALL I2C_write
    LDI   R16, DATA_MODE
    RCALL I2C_write
    
; Display "HUM: " text (continued)
   LDI   R24, 'H'
   RCALL process_char
   LDI   R24, 'U'
   RCALL process_char
   LDI   R24, 'M'
   RCALL process_char
   LDI   R24, ':'
   RCALL process_char
   LDI   R24, ' '
   RCALL process_char
   
   ; Convert humidity to ASCII digits
   MOV   R24, R26         ; Copy humidity to R24
   
   ; Divide by 10 to get tens digit
   LDI   R18, 10
   RCALL divide_display   ; R24 = quotient (tens), R19 = remainder (ones)
   
   ; Display tens digit
   SUBI  R24, -'0'        ; Convert to ASCII ('0' = 48)
   RCALL process_char     ; Display tens digit
   
   ; Display ones digit
   MOV   R24, R19         ; Move remainder to R24
   SUBI  R24, -'0'        ; Convert to ASCII
   RCALL process_char     ; Display ones digit
   
   ; Display percentage symbol (%)
   LDI   R24, '%'
   RCALL process_char
   
   ; End I2C transaction
   RCALL I2C_stop
   RET

;=====================================================================
; Division for display (separate from print_decimal function)
;=====================================================================
divide_display:
   LDI   R19, 0           ; Initialize remainder to 0
divide_display_loop:
   CP    R24, R18         ; Compare dividend with divisor
   BRLO  divide_display_done  ; Branch if lower (division complete)
   SUB   R24, R18         ; Subtract divisor from dividend
   INC   R19              ; Increment quotient
   RJMP  divide_display_loop   ; Continue division
divide_display_done:
   ; At this point, R24 contains remainder and R19 contains quotient
   ; Swap them for conventional output
   MOV   R23, R24         ; Temporarily store remainder
   MOV   R24, R19         ; Move quotient to R24
   MOV   R19, R23         ; Move remainder to R19
   RET

;=====================================================================
; Function to display a null-terminated string from program memory
;=====================================================================
display_string:
   ; Save working registers
   PUSH  R24
   PUSH  R16
   PUSH  R17
   PUSH  R18
   PUSH  R19
   
   ; Start I2C communication for the entire string
   RCALL I2C_start
   LDI   R16, (SSD1306_ADDR<<1)
   RCALL I2C_write
   LDI   R16, DATA_MODE
   RCALL I2C_write
   
display_string_loop:
   ; Load character from program memory and increment Z
   LPM   R24, Z+
   
   ; Check for end of string (null terminator)
   CPI   R24, 0
   BREQ  display_string_end
   
   ; Process character based on its type
   RCALL process_char
   
   ; Continue with next character
   RJMP  display_string_loop
   
display_string_end:
   ; End the I2C transaction
   RCALL I2C_stop
   
   ; Restore working registers
   POP   R19
   POP   R18
   POP   R17
   POP   R16
   POP   R24
   RET

;=====================================================================
; Process a single character for string display
;=====================================================================
process_char:
   ; Push registers
   PUSH  ZL
   PUSH  ZH
   
   ; Check if it's a space
   CPI   R24, ' '
   BRNE  process_not_space
   
   ; For space, just send 6 empty columns
   LDI   R19, 6           ; Width of space character
process_space_loop:
   LDI   R16, 0x00        ; All pixels off
   RCALL I2C_write
   DEC   R19
   BRNE  process_space_loop
   RJMP  process_char_done
   
process_not_space:
   ; Handle different character ranges
   ; Check for numbers (0-9)
   CPI   R24, '0'
   BRLO  process_not_number
   CPI   R24, '9'+1
   BRSH  process_not_number
   
   ; Handle number characters (0-9)
   SUBI  R24, '0'         ; Convert '0'-'9' to 0-9
   SUBI  R24, -26         ; Add 26 to skip past the letters (A-Z)
   RJMP  process_get_font_data
   
process_not_number:
   ; Check for uppercase letters (A-Z)
   CPI   R24, 'A'
   BRLO  process_not_uppercase
   CPI   R24, 'Z'+1
   BRSH  process_not_uppercase
   
   ; Get uppercase letter
   SUBI  R24, 'A'         ; Convert A-Z to 0-25
   RJMP  process_get_font_data
   
process_not_uppercase:
   ; Check for lowercase letters (a-z)
   CPI   R24, 'a'
   BRLO  process_check_symbols
   CPI   R24, 'z'+1
   BRSH  process_check_symbols
   
   ; Get lowercase (convert to uppercase for display)
   SUBI  R24, 'a'         ; Convert a-z to 0-25
   RJMP  process_get_font_data
   
process_check_symbols:
   ; Simple approach: handle a few common symbols directly
   CPI   R24, '.'
   BRNE  process_not_period
   LDI   R24, 36          ; Index for period
   RJMP  process_get_font_data
   
process_not_period:
   CPI   R24, ','
   BRNE  process_not_comma
   LDI   R24, 37
   RJMP  process_get_font_data
   
process_not_comma:
   CPI   R24, ':'
   BRNE  process_not_colon
   LDI   R24, 38
   RJMP  process_get_font_data
   
process_not_colon:
   CPI   R24, '!'
   BRNE  process_not_exclamation
   LDI   R24, 40
   RJMP  process_get_font_data
   
process_not_exclamation:
   CPI   R24, '?'
   BRNE  process_not_question
   LDI   R24, 41
   RJMP  process_get_font_data
   
process_not_question:
   CPI   R24, '-'
   BRNE  process_not_hyphen
   LDI   R24, 42
   RJMP  process_get_font_data
   
process_not_hyphen:
   CPI   R24, '/'
   BRNE  process_not_fslash
   LDI   R24, 44
   RJMP  process_get_font_data
   
process_not_fslash:
   CPI   R24, '%'
   BRNE  process_invalid_char
   LDI   R24, 43          ; Use the '+' character index for % symbol
   RJMP  process_get_font_data
   
process_get_font_data:
   ; Multiply by 5 (each character has 5 bytes in the lookup table)
   MOV   R18, R24         ; Copy offset
   LSL   R24              ; R24 *= 2
   LSL   R24              ; R24 *= 4
   ADD   R24, R18         ; R24 += R18 (original offset) to get R24 *= 5
   
   ; Load Z pointer to start of font data
   LDI   ZL, lo8(font_data)
   LDI   ZH, hi8(font_data)
   
   ; Add offset to Z pointer
   ADD   ZL, R24
   ADC   ZH, R1           ; R1 is assumed to be zero
   
   ; Output 5 bytes of character data
   LDI   R19, 5           ; 5 bytes per character
process_font_data_loop:
   LPM   R16, Z+          ; Load from program memory, increment Z
   RCALL I2C_write
   DEC   R19
   BRNE  process_font_data_loop
   
   ; Add a 1-pixel spacing after each character
   LDI   R16, 0x00
   RCALL I2C_write
   
   RJMP  process_char_done
   
process_invalid_char:
   ; For invalid characters, show as a filled rectangle
   LDI   R19, 5           ; Width of invalid character marker
process_invalid_char_loop:
   LDI   R16, 0x7E        ; Small box pattern
   RCALL I2C_write
   DEC   R19
   BRNE  process_invalid_char_loop
   
   ; Add a 1-pixel spacing after each character
   LDI   R16, 0x00
   RCALL I2C_write
   
process_char_done:
   ; Add 6 to column position for next character (5 pixels + 1 space)
   SUBI  R21, -6
   
   ; Restore Z and return
   POP   ZH
   POP   ZL
   RET

;=====================================================================
; Delay functions
;=====================================================================
delay_us:
    ; Microsecond delay (increased for reliability)
    LDI   R21, 80          ; Increase delay for I2C stability
delay_us_loop:
    NOP
    NOP
    DEC   R21
    BRNE  delay_us_loop
    RET

delay_ms:
    ; Millisecond delay
    LDI   R22, 200         ; Increased delay
delay_ms_outer:
    RCALL delay_us
    DEC   R22
    BRNE  delay_ms_outer
    RET

delay_sec:
    ; Second delay (from your original master code)
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

delay_long:
    ; Longer delay for testing
    LDI   R23, 10
delay_long_outer:
    RCALL delay_ms
    DEC   R23
    BRNE  delay_long_outer
    RET

delay_20ms:
    ; 20ms delay (from your original master code)
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

;=====================================================================
; Program Memory Data Section
;=====================================================================
.section .progmem.data, "a", @progbits
str_title:
   .ascii "WEATHER STATION"
   .byte 0  ; Null terminator

temp:
   .asciz "Threshold Temp: "
degree:
   .asciz " C"
cur_temp:
   .asciz "Current Temp: "
cur_humi:
   .asciz "Current Humi: "
percent:
   .asciz " %"

;=====================================================================
; Font data - 5x8 font for characters
;=====================================================================
font_data:
   ; A (0)
   .byte 0x7C, 0x12, 0x11, 0x12, 0x7C  ; A pattern
   
   ; B (1)
   .byte 0x7F, 0x49, 0x49, 0x49, 0x36  ; B pattern
   
   ; C (2)
   .byte 0x3E, 0x41, 0x41, 0x41, 0x22  ; C pattern
   
   ; D (3)
   .byte 0x7F, 0x41, 0x41, 0x22, 0x1C  ; D pattern
   
   ; E (4)
   .byte 0x7F, 0x49, 0x49, 0x49, 0x41  ; E pattern
   
   ; F (5)
   .byte 0x7F, 0x09, 0x09, 0x09, 0x01  ; F pattern
   
   ; G (6)
   .byte 0x3E, 0x41, 0x49, 0x49, 0x7A  ; G pattern
   
   ; H (7)
   .byte 0x7F, 0x08, 0x08, 0x08, 0x7F  ; H pattern
   
   ; I (8)
   .byte 0x00, 0x41, 0x7F, 0x41, 0x00  ; I pattern
   
   ; J (9)
   .byte 0x20, 0x40, 0x41, 0x3F, 0x01  ; J pattern
   
   ; K (10)
   .byte 0x7F, 0x08, 0x14, 0x22, 0x41  ; K pattern
   
   ; L (11)
   .byte 0x7F, 0x40, 0x40, 0x40, 0x40  ; L pattern
   
   ; M (12)
   .byte 0x7F, 0x02, 0x0C, 0x02, 0x7F  ; M pattern
   
   ; N (13)
   .byte 0x7F, 0x04, 0x08, 0x10, 0x7F  ; N pattern
   
   ; O (14)
   .byte 0x3E, 0x41, 0x41, 0x41, 0x3E  ; O pattern
   
   ; P (15)
   .byte 0x7F, 0x09, 0x09, 0x09, 0x06  ; P pattern
   
   ; Q (16)
   .byte 0x3E, 0x41, 0x51, 0x21, 0x5E  ; Q pattern
   
   ; R (17)
   .byte 0x7F, 0x09, 0x19, 0x29, 0x46  ; R pattern
   
   ; S (18)
   .byte 0x46, 0x49, 0x49, 0x49, 0x31  ; S pattern
   
   ; T (19)
   .byte 0x01, 0x01, 0x7F, 0x01, 0x01  ; T pattern
   
   ; U (20)
   .byte 0x3F, 0x40, 0x40, 0x40, 0x3F  ; U pattern
   
   ; V (21)
   .byte 0x1F, 0x20, 0x40, 0x20, 0x1F  ; V pattern
   
   ; W (22)
   .byte 0x3F, 0x40, 0x38, 0x40, 0x3F  ; W pattern
   
   ; X (23)
   .byte 0x63, 0x14, 0x08, 0x14, 0x63  ; X pattern
   
   ; Y (24)
   .byte 0x07, 0x08, 0x70, 0x08, 0x07  ; Y pattern
   
   ; Z (25)
   .byte 0x61, 0x51, 0x49, 0x45, 0x43  ; Z pattern

   ; Numbers (0-9)
   ; 0 
   .byte 0x3E, 0x51, 0x49, 0x45, 0x3E  ; 0 pattern
   
   ; 1
   .byte 0x00, 0x42, 0x7F, 0x40, 0x00  ; 1 pattern
   
   ; 2
   .byte 0x42, 0x61, 0x51, 0x49, 0x46  ; 2 pattern
   
   ; 3
   .byte 0x21, 0x41, 0x45, 0x4B, 0x31  ; 3 pattern
   
   ; 4
   .byte 0x18, 0x14, 0x12, 0x7F, 0x10  ; 4 pattern
   
   ; 5
   .byte 0x27, 0x45, 0x45, 0x45, 0x39  ; 5 pattern
   
   ; 6
   .byte 0x3C, 0x4A, 0x49, 0x49, 0x30  ; 6 pattern
   
   ; 7
   .byte 0x01, 0x71, 0x09, 0x05, 0x03  ; 7 pattern
   
   ; 8
   .byte 0x36, 0x49, 0x49, 0x49, 0x36  ; 8 pattern
   
   ; 9
   .byte 0x06, 0x49, 0x49, 0x29, 0x1E  ; 9 pattern

   ; Symbols
   ; . (period)
   .byte 0x00, 0x60, 0x60, 0x00, 0x00  ; Period pattern
   
   ; , (comma)
   .byte 0x00, 0x50, 0x30, 0x00, 0x00  ; Comma pattern
   
   ; : (colon)
   .byte 0x00, 0x36, 0x36, 0x00, 0x00  ; Colon pattern
   
   ; ; (semicolon)
   .byte 0x00, 0x56, 0x36, 0x00, 0x00  ; Semicolon pattern
   
   ; ! (exclamation)
   .byte 0x00, 0x5F, 0x00, 0x00, 0x00  ; Exclamation pattern
   
   ; ? (question mark)
   .byte 0x02, 0x01, 0x51, 0x09, 0x06  ; Question mark pattern
   
   ; - (hyphen)
   .byte 0x08, 0x08, 0x08, 0x08, 0x08  ; Hyphen pattern
   
   ; + (plus)
   .byte 0x08, 0x08, 0x3E, 0x08, 0x08  ; Plus pattern
   
   ; / (forward slash)
   .byte 0x18, 0x0C, 0x06, 0x03, 0x01  ; Forward slash pattern