;==============================================
; Master-Slave I2C Energy Monitoring System
; 
; Arduino Master: 
; - Membaca tegangan (ZMPT101B pada A0)
; - Membaca arus (ACS712 pada A1)
; - Menghitung daya
; - Mengirim data ke Slave melalui I2C
; - Menampilkan di OLED dan Serial Monitor
; - Kontrol LED dan Buzzer berdasarkan konsumsi daya
; 
; Arduino Slave:
; - Menerima data dari Master
; - Menampilkan ke Serial Monitor
; - Menampilkan di OLED
;==============================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"
#include "avr/interrupt.h"

; I2C dan OLED definitions
#define SDA_PIN 4       ; PC4 (A4) untuk I2C
#define SCL_PIN 5       ; PC5 (A5) untuk I2C
#define SSD1306_ADDR 0x3C
#define COMMAND_MODE 0x00
#define DATA_MODE 0x40

; Alamat I2C
#define MASTER_ADDR 0x42
#define SLAVE_ADDR 0x08

; Pin assignments
#define VOLTAGE_PIN 0   ; A0 untuk sensor ZMPT101B
#define CURRENT_PIN 1   ; A1 untuk sensor ACS712
#define LED_PIN 2       ; D2 untuk LED warning
#define BUZZER_PIN 3    ; D3 untuk Buzzer
#define BUTTON_PIN 2    ; INT0 (D2) pada Slave untuk reset

; Threshold values (dapat disesuaikan)
#define POWER_WARNING_THRESHOLD 100    ; Nilai daya untuk peringatan (LED berkedip)
#define POWER_ALARM_THRESHOLD 150      ; Nilai daya untuk alarm (LED + buzzer)

;===============================================================
; Global variables
;===============================================================
.section .data
    voltage:        .byte 0, 0    ; 16-bit nilai tegangan
    current:        .byte 0, 0    ; 16-bit nilai arus
    power:          .byte 0, 0    ; 16-bit nilai daya
    temperature:    .byte 0       ; 8-bit nilai suhu
    humidity:       .byte 0       ; 8-bit nilai kelembaban
    power_status:   .byte 0       ; 0=normal, 1=warning, 2=alarm
    device_mode:    .byte 0       ; 0=master, 1=slave

;===============================================================
; Program entry
;===============================================================
.global main

main:
    ; Menentukan apakah device ini Master atau Slave
    ; Dalam contoh ini, kita menggunakan jumper pada D8
    ; - Jika D8 terhubung ke GND, maka device adalah Slave
    ; - Jika D8 tidak terhubung (pull-up), maka device adalah Master
    SBI   DDRB, 0           ; PB0 (D8) sebagai input dengan pull-up
    SBI   PORTB, 0          ; Enable pull-up resistor
    
    ; Tunggu sedikit untuk stabilisasi pin
    RCALL delay_ms
    
    ; Baca status PB0
    IN    R16, PINB
    ANDI  R16, 0x01         ; Ambil hanya bit 0
    CPI   R16, 0x01         ; Jika high, maka Master
    BRNE  init_slave        ; Jika low, maka Slave

init_master:
    ; Inisialisasi sebagai Master
    LDI   R16, 0
    STS   device_mode, R16  ; Set mode sebagai Master
    RCALL init_master_device
    RJMP  main_loop

init_slave:
    ; Inisialisasi sebagai Slave
    LDI   R16, 1
    STS   device_mode, R16  ; Set mode sebagai Slave
    RCALL init_slave_device
    RJMP  main_loop

;===============================================================
; Main program loop
;===============================================================
main_loop:
    ; Check device mode
    LDS   R16, device_mode
    CPI   R16, 0
    BREQ  master_loop
    RJMP  slave_loop

;===============================================================
; Main loop for Master device
;===============================================================
master_loop:
    ; Read sensors
    RCALL read_voltage
    RCALL read_current
    RCALL calculate_power
    RCALL check_power_status
    RCALL update_indicators
    
    ; Read DHT11 for temperature and humidity
    RCALL read_dht11
    
    ; Display data on OLED
    RCALL display_master_data
    
    ; Send data to Slave via I2C
    RCALL send_data_to_slave
    
    ; Delay before next loop
    RCALL delay_sec
    RJMP  master_loop

;===============================================================
; Main loop for Slave device
;===============================================================
slave_loop:
    ; Listen for I2C data from Master
    RCALL listen_i2c
    
    ; Display received data on OLED
    RCALL display_slave_data
    
    ; Delay before next loop
    RCALL delay_sec
    RJMP  slave_loop

;===============================================================
; Initialize master device
;===============================================================
init_master_device:
    ; Inisialisasi port untuk sensor dan output
    CBI   DDRC, VOLTAGE_PIN    ; A0 sebagai input untuk sensor tegangan
    CBI   DDRC, CURRENT_PIN    ; A1 sebagai input untuk sensor arus
    SBI   DDRD, LED_PIN        ; D2 sebagai output untuk LED
    SBI   DDRD, BUZZER_PIN     ; D3 sebagai output untuk Buzzer
    
    ; Inisialisasi ADC
    LDI   R20, 0x40            ; AVCC sebagai reference, right justify
    STS   ADMUX, R20
    LDI   R20, 0x87            ; ADC Enable, prescaler 128
    STS   ADCSRA, R20
    
    ; Inisialisasi Serial
    RCALL init_serial
    
    ; Inisialisasi I2C Master
    RCALL init_i2c_master
    
    ; Inisialisasi OLED
    RCALL I2C_init             ; Initialize I2C untuk OLED
    RCALL SSD1306_init         ; Initialize OLED display
    RCALL clear_screen         ; Clear display
    
    ; Print welcome message
    LDI   ZL, lo8(msg_master)
    LDI   ZH, hi8(msg_master)
    RCALL print_string
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit
    
    RET

;===============================================================
; Initialize slave device
;===============================================================
init_slave_device:
    ; Inisialisasi port
    CBI   DDRD, BUTTON_PIN     ; D2 sebagai input untuk button reset
    SBI   PORTD, BUTTON_PIN    ; Enable pull-up resistor
    
    ; Inisialisasi interrupt untuk button
    LDI   R16, (1<<ISC01)      ; Trigger INT0 on falling edge
    STS   EICRA, R16
    LDI   R16, (1<<INT0)       ; Enable INT0 interrupt
    OUT   EIMSK, R16
    SEI                        ; Enable global interrupts
    
    ; Inisialisasi Serial
    RCALL init_serial
    
    ; Inisialisasi I2C Slave
    RCALL init_i2c_slave
    
    ; Inisialisasi OLED
    RCALL I2C_init             ; Initialize I2C untuk OLED
    RCALL SSD1306_init         ; Initialize OLED display
    RCALL clear_screen         ; Clear display
    
    ; Print welcome message
    LDI   ZL, lo8(msg_slave)
    LDI   ZH, hi8(msg_slave)
    RCALL print_string
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit
    
    RET

;===============================================================
; I2C Master Initialization
;===============================================================
init_i2c_master:
    ; Inisialisasi TWI (I2C) sebagai Master
    LDI   R16, 0              ; Disable TWI
    STS   TWCR, R16
    
    ; Set bit rate register untuk 100kHz I2C clock (at 16Mhz CPU)
    LDI   R16, 72             ; (16MHz / (16 + 2*72*1)) = 100kHz
    STS   TWBR, R16
    
    ; Set prescaler value = 1
    LDI   R16, 0
    STS   TWSR, R16
    
    ; Enable TWI
    LDI   R16, (1<<TWEN)
    STS   TWCR, R16
    
    RET

;===============================================================
; I2C Slave Initialization
;===============================================================
init_i2c_slave:
    ; Inisialisasi TWI (I2C) sebagai Slave
    LDI   R16, 0              ; Disable TWI
    STS   TWCR, R16
    
    ; Set slave address
    LDI   R16, SLAVE_ADDR
    STS   TWAR, R16
    
    ; Enable TWI and ACK
    LDI   R16, (1<<TWEA) | (1<<TWEN)
    STS   TWCR, R16
    
    RET

;===============================================================
; I2C Master: Send data to Slave
;===============================================================
send_data_to_slave:
    ; Start condition
    LDI   R16, (1<<TWINT) | (1<<TWSTA) | (1<<TWEN)
    STS   TWCR, R16

wait_start:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_start

    ; Check if start condition was transmitted successfully
    LDS   R16, TWSR
    ANDI  R16, 0xF8       ; Mask prescaler bits
    CPI   R16, 0x08       ; Start condition transmitted
    BRNE  i2c_error

    ; Load slave address and write bit (0)
    LDI   R16, (SLAVE_ADDR << 1)
    STS   TWDR, R16

    ; Transmit slave address
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_addr:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_addr

    ; Check if SLA+W was transmitted and ACK received
    LDS   R16, TWSR
    ANDI  R16, 0xF8       ; Mask prescaler bits
    CPI   R16, 0x18       ; SLA+W transmitted, ACK received
    BRNE  i2c_error

    ; Send header byte (0xAA)
    LDI   R16, 0xAA
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data1:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data1

    ; Send voltage (LSB)
    LDS   R16, voltage
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data2:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data2

    ; Send voltage (MSB)
    LDS   R16, voltage+1
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data3:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data3

    ; Send current (LSB)
    LDS   R16, current
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data4:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data4

    ; Send current (MSB)
    LDS   R16, current+1
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data5:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data5

    ; Send power (LSB)
    LDS   R16, power
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data6:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data6

    ; Send power (MSB)
    LDS   R16, power+1
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data7:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data7

    ; Send temperature
    LDS   R16, temperature
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data8:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data8

    ; Send humidity
    LDS   R16, humidity
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data9:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data9

    ; Send status byte
    LDS   R16, power_status
    STS   TWDR, R16
    LDI   R16, (1<<TWINT) | (1<<TWEN)
    STS   TWCR, R16

wait_data10:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_data10

    ; Send stop condition
    LDI   R16, (1<<TWINT) | (1<<TWEN) | (1<<TWSTO)
    STS   TWCR, R16

    ; Print sent message to serial
    LDI   ZL, lo8(msg_sent)
    LDI   ZH, hi8(msg_sent)
    RCALL print_string

    RET

i2c_error:
    ; Send stop condition on error
    LDI   R16, (1<<TWINT) | (1<<TWEN) | (1<<TWSTO)
    STS   TWCR, R16
    
    ; Print error to serial
    LDI   ZL, lo8(msg_i2c_error)
    LDI   ZH, hi8(msg_i2c_error)
    RCALL print_string
    
    RET

;===============================================================
; I2C Slave: Listen for data from Master
;===============================================================
listen_i2c:
    ; Enable TWI and ACK
    LDI   R16, (1<<TWEA) | (1<<TWEN) | (1<<TWINT)
    STS   TWCR, R16

wait_event:
    ; Wait for TWINT flag set
    LDS   R16, TWCR
    SBRS  R16, TWINT
    RJMP  wait_event

    ; Get status code
    LDS   R16, TWSR
    ANDI  R16, 0xF8       ; Mask prescaler bits
    
    ; Check for Start+ADDR received
    CPI   R16, 0x60       ; Own SLA+W has been received; ACK returned
    BRNE  check_data_received
    
    ; Ready to receive data bytes
    LDI   R16, (1<<TWEA) | (1<<TWEN) | (1<<TWINT)
    STS   TWCR, R16
    RJMP  wait_event
    
check_data_received:
    ; Check for data received
    CPI   R16, 0x80       ; Previously addressed with own SLA+W; data received; ACK returned
    BRNE  check_stop
    
    ; Read data byte
    LDS   R17, TWDR       ; Get received data
    
    ; Check for header byte
    CPI   R17, 0xAA
    BRNE  not_header
    
    ; Prepare to receive actual data bytes
    LDI   R19, 0          ; Data counter
    
    ; ACK and wait for next byte
    LDI   R16, (1<<TWEA) | (1<<TWEN) | (1<<TWINT)
    STS   TWCR, R16
    RJMP  wait_event
    
not_header:
    ; Process received data based on counter
    INC   R19             ; Increment data counter
    
    CPI   R19, 1
    BRNE  check_byte2
    ; First data byte - voltage LSB
    STS   voltage, R17
    RJMP  ack_next_byte
    
check_byte2:
    CPI   R19, 2
    BRNE  check_byte3
    ; Second data byte - voltage MSB
    STS   voltage+1, R17
    RJMP  ack_next_byte
    
check_byte3:
    CPI   R19, 3
    BRNE  check_byte4
    ; Third data byte - current LSB
    STS   current, R17
    RJMP  ack_next_byte
    
check_byte4:
    CPI   R19, 4
    BRNE  check_byte5
    ; Fourth data byte - current MSB
    STS   current+1, R17
    RJMP  ack_next_byte
    
check_byte5:
    CPI   R19, 5
    BRNE  check_byte6
    ; Fifth data byte - power LSB
    STS   power, R17
    RJMP  ack_next_byte
    
check_byte6:
    CPI   R19, 6
    BRNE  check_byte7
    ; Sixth data byte - power MSB
    STS   power+1, R17
    RJMP  ack_next_byte
    
check_byte7:
    CPI   R19, 7
    BRNE  check_byte8
    ; Seventh data byte - temperature
    STS   temperature, R17
    RJMP  ack_next_byte
    
check_byte8:
    CPI   R19, 8
    BRNE  check_byte9
    ; Eighth data byte - humidity
    STS   humidity, R17
    RJMP  ack_next_byte
    
check_byte9:
    CPI   R19, 9
    BRNE  ack_next_byte
    ; Ninth data byte - status
    STS   power_status, R17
    
    ; Print confirmation to serial
    LDI   ZL, lo8(msg_received)
    LDI   ZH, hi8(msg_received)
    RCALL print_string
    
ack_next_byte:
    ; ACK and wait for next byte
    LDI   R16, (1<<TWEA) | (1<<TWEN) | (1<<TWINT)
    STS   TWCR, R16
    RJMP  wait_event

check_stop:
    ; Check for Stop condition
    CPI   R16, 0xA0       ; A STOP condition or repeated START has been received
    BRNE  other_state
    
    ; ACK future transactions
    LDI   R16, (1<<TWEA) | (1<<TWEN) | (1<<TWINT)
    STS   TWCR, R16

    RET
    
other_state:
    ; Handle other states
    LDI   R16, (1<<TWEA) | (1<<TWEN) | (1<<TWINT)
    STS   TWCR, R16
    
    RET

;===============================================================
; Read voltage sensor (ZMPT101B on A0)
;===============================================================
read_voltage:
    ; Set ADC channel to A0
    LDI   R20, 0x40       ; AVCC reference, right justified, ADC0
    STS   ADMUX, R20
    
    ; Start ADC conversion
    LDI   R20, 0xC7       ; ADC Enable, Start Conversion, Prescaler 128
    STS   ADCSRA, R20
    
wait_voltage_adc:
    ; Wait for ADC completion
    LDS   R21, ADCSRA
    SBRS  R21, 4          ; Test ADIF flag
    RJMP  wait_voltage_adc
    
    ; Clear ADIF flag
    LDI   R17, 0xD7
    STS   ADCSRA, R17
    
    ; Read ADC result (10-bit value)
    LDS   R16, ADCL       ; Must read ADCL first
    LDS   R17, ADCH
    
    ; Save raw value
    STS   voltage, R16
    STS   voltage+1, R17
    
    ; Convert to actual voltage (simplified)
    ; In real system we'd need to do proper scaling
    
    ; Print voltage value to serial
    LDI   ZL, lo8(msg_voltage)
    LDI   ZH, hi8(msg_voltage)
    RCALL print_string
    
    MOV   R24, R17
    RCALL print_decimal
    MOV   R24, R16
    RCALL print_decimal
    
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit
    
    RET

;===============================================================
; Read current sensor (ACS712 on A1)
;===============================================================
read_current:
    ; Set ADC channel to A1
    LDI   R20, 0x41       ; AVCC reference, right justified, ADC1
    STS   ADMUX, R20
    
    ; Start ADC conversion
    LDI   R20, 0xC7       ; ADC Enable, Start Conversion, Prescaler 128
    STS   ADCSRA, R20
    
wait_current_adc:
    ; Wait for ADC completion
    LDS   R21, ADCSRA
    SBRS  R21, 4          ; Test ADIF flag
    RJMP  wait_current_adc
    
    ; Clear ADIF flag
    LDI   R17, 0xD7
    STS   ADCSRA, R17
    
    ; Read ADC result (10-bit value)
    LDS   R16, ADCL       ; Must read ADCL first
    LDS   R17, ADCH
    
    ; Save raw value
    STS   current, R16
    STS   current+1, R17
    
    ; Convert to actual current (simplified)
    ; In real system we'd need to do proper scaling
    
    ; Print current value to serial
    LDI   ZL, lo8(msg_current)
    LDI   ZH, hi8(msg_current)
    RCALL print_string
    
    MOV   R24, R17
    RCALL print_decimal
    MOV   R24, R16
    RCALL print_decimal
    
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit
    
    RET

;===============================================================
; Calculate power from voltage and current
;===============================================================
calculate_power:
    ; P = V * I (simplified multiplication)
    ; For 16-bit by 16-bit multiplication, use a simplified approach here
    LDS   R22, voltage        ; Load voltage LSB
    LDS   R23, voltage+1      ; Load voltage MSB
    LDS   R24, current        ; Load current LSB
    LDS   R25, current+1      ; Load current MSB
    
    ; We'll use simple multiplication method for 8-bit values (MSB only)
    ; In real application, proper 16x16 multiplication would be needed
    MUL   R23, R25           ; Multiply voltage MSB with current MSB
    STS   power, R0
    STS   power+1, R1
    
    ; Print power to serial
    LDI   ZL, lo8(msg_power)
    LDI   ZH, hi8(msg_power)
    RCALL print_string
    
    LDS   R24, power+1
    RCALL print_decimal
    LDS   R24, power
    RCALL print_decimal
    
    LDI   R24, 'W'
    RCALL uart_transmit
    LDI   R24, 0x0D
    RCALL uart_transmit
    LDI   R24, 0x0A
    RCALL uart_transmit
    
    RET

;===============================================================
; Check power status against thresholds
;===============================================================
check_power_status:
    LDS   R16, power+1    ; MSB of power
    LDS   R17, power      ; LSB of power
    
    ; Check against alarm threshold
    CPI   R16, 0          ; Compare MSB with 0
    BRNE  set_alarm       ; If MSB > 0, set alarm
    CPI   R17, POWER_ALARM_THRESHOLD
    BRSH  set_alarm
    
    ; Check against warning threshold
    CPI   R17, POWER_WARNING_THRESHOLD
    BRSH  set_warning
    
    ; Normal status
    LDI   R18, 0
    STS   power_status, R18
    RET
    
set_warning:
    LDI   R18, 1
    STS   power_status, R18
    RET
    
set_alarm:
    LDI   R18, 2
    STS   power_status, R18
    RET

;===============================================================
; Update LED and buzzer based on power status
;===============================================================
update_indicators:
    LDS   R16, power_status
    
    CPI   R16, 0
    BREQ  status_normal
    
    CPI   R16, 1
    BREQ  status_warning
    
    ; Status is alarm
    SBI   PORTD, LED_PIN      ; LED ON
    SBI   PORTD, BUZZER_PIN   ; Buzzer ON
    
    ; Print alarm status
    LDI   ZL, lo8(msg_alarm)
    LDI   ZH, hi8(msg_alarm)
    RCALL print_string
    RET
    
status_warning:
    ; Blink LED but keep buzzer off
    IN    R17, PORTD
    LDI   R18, (1<<LED_PIN)
    EOR   R17, R18            ; Toggle LED bit
    OUT   PORTD, R17
    CBI   PORTD, BUZZER_PIN   ; Ensure buzzer is off
    
    ; Print warning status
    LDI   ZL, lo8(msg_warning)
    LDI   ZH, hi8(msg_warning)
    RCALL print_string
    RET
    
status_normal:
    CBI   PORTD, LED_PIN      ; LED OFF
    CBI   PORTD, BUZZER_PIN   ; Buzzer OFF
    
    ; Print normal status
    LDI   ZL, lo8(msg_normal)
    LDI   ZH, hi8(msg_normal)
    RCALL print_string
    RET

;===============================================================
; DHT11 Reading Routine (for temperature and humidity)
;===============================================================
read_dht11:
    ; Based on previous DHT11 code provided
    ; Start signal to DHT11
    SBI   DDRB, 1
    CBI   PORTB, 1
    RCALL delay_20ms
    SBI   PORTB, 1
    
    ; Wait for DHT11 response
    CBI   DDRB, 1
w1: SBIC  PINB, 1
    RJMP  w1
    
    ; Delay for DHT11 to prepare data
    RCALL delay_40us
    
    ; Read 5 bytes from DHT11
    LDI   R20, 5          ; 5 bytes to read
    LDI   ZL, 0           ; Zero out ZL
    LDI   ZH, 0           ; Zero out ZH
read_dht11_loop:
    ; Wait for start of byte (low signal)
    CBI   DDRB, 1
w2: SBIC  PINB, 1
    RJMP  w2
    
    ; Wait for end of byte (high signal)
    CBI   DDRB, 1
w3: SBIC  PINB, 1
    RJMP  w3
    
    ; Read byte
    RCALL read_dht11_byte
    
    ; Decrement counter and check if done
    DEC   R20
    BRNE  read_dht11_loop
    
    ; DHT11 data read complete
    ; Data is now in voltage, current, power, temperature, humidity
    RET

;===============================================================
; Read a byte from DHT11 (called by read_dht11)
;===============================================================
read_dht11_byte:
    LDI   R18, 8          ; 8 bits per byte
    LDI   R16, 0          ; Clear R16 for receiving byte
read_dht11_bit:
    ; Wait for start of bit (low signal)
    CBI   DDRB, 1
w4: SBIC  PINB, 1
    RJMP  w4
    
    ; Wait for end of bit (high signal)
    CBI   DDRB, 1
w5: SBIC  PINB, 1
    RJMP  w5
    
    ; Shift in bit to R16
    LSL   R16
    TST   PINB
    BRCC  read_dht11_bit_1
    LDI   R16, 0
    RJMP  read_dht11_bit_next
read_dht11_bit_1:
    LDI   R16, 1
read_dht11_bit_next:
    DEC   R18
    BRNE  read_dht11_bit
    
    ; Store received byte (R16) to appropriate variable
    ; Assuming order: voltage, current, power, temperature, humidity
    CPI   R20, 4          ; Check if reading power (byte 4)
    BREQ  store_power
    CPI   R20, 3          ; Check if reading temperature (byte 3)
    BREQ  store_temperature
    CPI   R20, 2          ; Check if reading humidity (byte 2)
    BREQ  store_humidity
    RJMP  read_dht11_done
store_power:
    STS   power, R16
    RJMP  read_dht11_done
store_temperature:
    STS   temperature, R16
    RJMP  read_dht11_done
store_humidity:
    STS   humidity, R16
read_dht11_done:
    RET

;===============================================================
; Delay routines
;===============================================================
delay_ms:
    ; Delay approximately 1 millisecond
    LDI   R18, 250         ; 250 cycles for ~1ms at 16MHz
    LDI   R19, 0
delay_ms_loop:
    NOP
    NOP
    DEC   R18
    BRNE  delay_ms_loop
    RET

delay_sec:
    ; Delay approximately 1 second
    LDI   R18, 0
    LDI   R19, 61         ; 61 ms loops for ~1s at 16MHz
delay_sec_loop:
    RCALL delay_ms
    DEC   R19
    BRNE  delay_sec_loop
    RET

;===============================================================
; UART and Serial routines
;===============================================================
init_serial:
    ; Inisialisasi UART untuk komunikasi serial
    LDI   R16, (1<<RXEN) | (1<<TXEN)    ; Enable receiver and transmitter
    STS   UCSR0B, R16
    
    LDI   R16, (1<<UCSZ21) | (1<<UCSZ20)    ; 8 data bits, no parity, 1 stop bit
    STS   UCSR0C, R16
    
    LDI   R16, 51         ; Set baud rate to 9600 (assuming 16MHz clock)
    STS   UBRR0L, R16
    LDI   R16, 0
    STS   UBRR0H, R16
    
    RET

uart_transmit:
    ; Transmit one byte in R24 via UART
    OUT   UDR0, R24
wait_uart:
    ; Wait for transmission complete
    LDS   R16, UCSR0A
    SBRS  R16, TXC0
    RJMP  wait_uart
    RET

uart_receive:
    ; Receive one byte via UART to R24
    wait_uart_receive:
    LDS   R16, UCSR0A
    SBRS  R16, RXC0
    RJMP  wait_uart_receive
    LDS   R24, UDR0
    RET

;===============================================================
; String and data printing routines
;===============================================================
print_string:
    ; Print null-terminated string at Z pointer via UART
    LD    R30, ZL
    LD    R31, ZH
print_string_loop:
    LD    R24, Z+
    CPI   R24, 0
    BEQ   print_string_done
    RCALL uart_transmit
    RJMP  print_string_loop
print_string_done:
    RET

print_decimal:
    ; Print decimal value in R24:R25 via UART
    ; Assumes R24:R25 contains the value to print
    ; Uses simple division by 10 method
    LDI   R20, 10         ; Divisor
    CLR   R22             ; Clear R22 for storing digits
print_decimal_loop:
    ; Divide R24:R25 by 10
    MOV   R0, R24
    MOV   R1, R25
    CLR   R24
    CLR   R25
    DIV   R20
    
    ; Store remainder (digit) in R22
    ADD   R22, R0
    
    ; Check if quotient is zero
    MOV   R24, R1
    OR    R24, R0
    BREQ  print_decimal_done
    
    ; Not done, continue dividing
    RJMP  print_decimal_loop
print_decimal_done:
    ; R22 now contains the reversed decimal digits
    ; Need to reverse it back and print
    LDI   R20, 3          ; Assuming max 3 digits for power (0-255)
    LDI   R30, 0          ; Z pointer for storing string
reverse_decimal_loop:
    MOV   R24, R22
    ANDI  R24, 0x0F
    CPI   R24, 10
    BRLT  print_decimal_store_digit
    LDI   R24, 'A'-10
    ADD   R24, R24
    LDI   R25, 0
    RCALL uart_transmit
    RJMP  reverse_decimal_done
print_decimal_store_digit:
    ADDI  R24, 48         ; Convert to ASCII
    RCALL uart_transmit
reverse_decimal_done:
    ; Done printing decimal value
    RET

;===============================================================
; OLED Display Integration
;===============================================================
oled_display:
    ; Initialize OLED (if not already initialized)
    RCALL oled_init

    ; Display voltage
    LDI   ZL, lo8(voltage_msg)
    LDI   ZH, hi8(voltage_msg)
    RCALL oled_print_string
    LDS   R16, voltage
    RCALL oled_print_number

    ; Display current
    LDI   ZL, lo8(current_msg)
    LDI   ZH, hi8(current_msg)
    RCALL oled_print_string
    LDS   R16, current
    RCALL oled_print_number

    ; Display power
    LDI   ZL, lo8(power_msg)
    LDI   ZH, hi8(power_msg)
    RCALL oled_print_string
    LDS   R16, power
    RCALL oled_print_number

    ; Display temperature
    LDI   ZL, lo8(temp_msg)
    LDI   ZH, hi8(temp_msg)
    RCALL oled_print_string
    LDS   R16, temperature
    RCALL oled_print_number

    ; Display humidity
    LDI   ZL, lo8(humidity_msg)
    LDI   ZH, hi8(humidity_msg)
    RCALL oled_print_string
    LDS   R16, humidity
    RCALL oled_print_number

    RET

;===============================================================
; Serial Monitor Output
;===============================================================
serial_monitor:
    ; Print voltage
    LDI   ZL, lo8(voltage_msg)
    LDI   ZH, hi8(voltage_msg)
    RCALL print_string
    LDS   R16, voltage
    RCALL print_number

    ; Print current
    LDI   ZL, lo8(current_msg)
    LDI   ZH, hi8(current_msg)
    RCALL print_string
    LDS   R16, current
    RCALL print_number

    ; Print power
    LDI   ZL, lo8(power_msg)
    LDI   ZH, hi8(power_msg)
    RCALL print_string
    LDS   R16, power
    RCALL print_number

    ; Print temperature
    LDI   ZL, lo8(temp_msg)
    LDI   ZH, hi8(temp_msg)
    RCALL print_string
    LDS   R16, temperature
    RCALL print_number

    ; Print humidity
    LDI   ZL, lo8(humidity_msg)
    LDI   ZH, hi8(humidity_msg)
    RCALL print_string
    LDS   R16, humidity
    RCALL print_number

    RET

;===============================================================
; Reset Button Interrupt
;===============================================================
reset_interrupt:
    ; Reset all variables to default state
    LDI   R16, 0x00
    STS   voltage, R16
    STS   current, R16
    STS   power, R16
    STS   temperature, R16
    STS   humidity, R16
    STS   power_status, R16

    ; Clear OLED display
    RCALL oled_clear

    ; Print reset message to serial
    LDI   ZL, lo8(reset_msg)
    LDI   ZH, hi8(reset_msg)
    RCALL print_string

    RET

;===============================================================
; LED and Buzzer Control
;===============================================================
led_buzzer_control:
    ; Check power status
    LDS   R16, power_status
    CPI   R16, 0x01       ; Check if power exceeds threshold
    BRNE  led_buzzer_off

    ; Turn on LED and buzzer
    SBI   PORTB, LED_PIN
    SBI   PORTB, BUZZER_PIN
    RJMP  led_buzzer_end

led_buzzer_off:
    ; Turn off LED and buzzer
    CBI   PORTB, LED_PIN
    CBI   PORTB, BUZZER_PIN

led_buzzer_end:
    RET

;===============================================================
; End of program
;===============================================================