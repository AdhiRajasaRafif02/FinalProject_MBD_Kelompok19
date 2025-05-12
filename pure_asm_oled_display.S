#define __SFR_OFFSET 0x00
#include "avr/io.h"

; I2C and SSD1306 definitions
#define SDA_PIN 4       ; PC4 (A4)
#define SCL_PIN 5       ; PC5 (A5)
#define SSD1306_ADDR 0x3C
#define COMMAND_MODE 0x00
#define DATA_MODE 0x40

;================================================================
; Arduino entry points - these must be global
.global setup
.global loop
;================================================================

; Arduino will call this function at startup
setup:
    RCALL I2C_init         ; Initialize I2C bus
    RCALL SSD1306_init     ; Initialize OLED display
    RCALL clear_screen     ; Clear the screen first
    
    ; Initialize temperature and humidity variables
    RCALL init_temp_humidity
    
    ; Display static text
    RCALL display_static_text
    
    ; Display initial temperature and humidity
    RCALL display_temperature
    RCALL display_humidity
    
    RET                    ; Return to Arduino core

; Arduino will call this repeatedly after setup
loop:
    ; Update and display temperature and humidity once per cycle
    RCALL update_temp_humidity   ; Update both values
    RCALL display_temperature    ; Display current temperature
    RCALL display_humidity       ; Display current humidity
    RCALL delay_long             ; Delay to make change visible
    RCALL delay_long             ; Extra delay for better visibility
    RCALL delay_long             ; Even more delay for slower changes
    RJMP loop                    ; Loop forever
    RET                          ; (This will never be reached)

;----------------------------------------------------------------
; Global variables (in registers)
; R25 will hold our current temperature value
; R26 will hold our current humidity value
;----------------------------------------------------------------

;----------------------------------------------------------------
; Initialize temperature and humidity variables
; Call this from setup to set the initial values
init_temp_humidity:
    LDI   R25, 25          ; Start at 25°C
    LDI   R26, 50          ; Start at 50% humidity
    RET

;----------------------------------------------------------------
; Update temperature and humidity values
update_temp_humidity:
    ; Update temperature (25-30°C range)
    INC   R25              ; Increment temperature
    CPI   R25, 31          ; Check if we reached 31
    BRNE  temp_ok
    LDI   R25, 25          ; Reset to 25 if we reached 31
temp_ok:

    ; Update humidity (50-65% range)
    INC   R26              ; Increment humidity
    CPI   R26, 66          ; Check if we reached 66
    BRNE  humidity_ok
    LDI   R26, 50          ; Reset to 50 if we reached 66
humidity_ok:
    RET

;----------------------------------------------------------------
; Convert temperature to ASCII and display it
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
    RCALL divide           ; R24 = quotient (tens), R19 = remainder (ones)
    
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

;----------------------------------------------------------------
; Convert humidity to ASCII and display it
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
    
    ; Display "HUM: " text
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
    RCALL divide           ; R24 = quotient (tens), R19 = remainder (ones)
    
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

;----------------------------------------------------------------
; Simple division routine
; Input: R24 = dividend, R18 = divisor
; Output: R24 = quotient, R19 = remainder
divide:
    LDI   R19, 0           ; Initialize remainder to 0
divide_loop:
    CP    R24, R18         ; Compare dividend with divisor
    BRLO  divide_done      ; Branch if lower (division complete)
    SUB   R24, R18         ; Subtract divisor from dividend
    INC   R19              ; Increment quotient
    RJMP  divide_loop      ; Continue division
divide_done:
    ; At this point, R24 contains remainder and R19 contains quotient
    ; Swap them for conventional output
    MOV   R23, R24         ; Temporarily store remainder
    MOV   R24, R19         ; Move quotient to R24
    MOV   R19, R23         ; Move remainder to R19
    RET

;----------------------------------------------------------------
; Display the static text (title)
display_static_text:
    ; Set cursor position for title
    LDI   R20, 1           ; Page 1 (top row)
    LDI   R21, 16          ; Column 16 (left-centered)
    RCALL set_cursor
    
    ; Display "WEATHER STATION"
    LDI   ZL, lo8(str_title)
    LDI   ZH, hi8(str_title)
    RCALL display_string
    
    RET

;================================================================
; I2C Functions
;================================================================
I2C_init:
    ; Set I2C pins as outputs initially
    SBI   DDRC, SDA_PIN    ; SDA as output
    SBI   DDRC, SCL_PIN    ; SCL as output
    ; Set both lines high (idle state)
    SBI   PORTC, SDA_PIN
    SBI   PORTC, SCL_PIN
    RCALL delay_ms         ; Stabilize
    RET

;----------------------------------------------------------------
I2C_start:
    SBI   PORTC, SDA_PIN   ; Ensure SDA is high
    SBI   PORTC, SCL_PIN   ; Ensure SCL is high
    RCALL delay_us
    CBI   PORTC, SDA_PIN   ; SDA goes low while SCL is high (START)
    RCALL delay_us
    CBI   PORTC, SCL_PIN   ; SCL low
    RET

;----------------------------------------------------------------
I2C_stop:
    CBI   PORTC, SDA_PIN   ; SDA low
    RCALL delay_us
    SBI   PORTC, SCL_PIN   ; SCL high
    RCALL delay_us
    SBI   PORTC, SDA_PIN   ; SDA high while SCL high (STOP)
    RCALL delay_ms         ; Extra delay after stop
    RET

;----------------------------------------------------------------
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

;================================================================
; SSD1306 Functions
;================================================================
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

;----------------------------------------------------------------
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

;----------------------------------------------------------------
; Position cursor at specified page and column
; Input: R20 = page (0-7), R21 = column (0-127)
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

;----------------------------------------------------------------
; Function to display a null-terminated string from program memory
; Input: Z register (ZL,ZH) pointing to string in program memory
; Using: R20 = page, R21 = column (should be set before calling)
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

;----------------------------------------------------------------
; Process a single character for string display
; Input: R24 = ASCII character to process
; Modifies: R16, R17, R18, R19, Z (temporarily)
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
    LDI   R24, 43          ; Use the '+' character index for % symbol (similar appearance)
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

;================================================================
; Font data - 5x8 font for A-Z
;================================================================
.section .progmem.data, "a", @progbits
str_title:
    .ascii "WEATHER STATION"
    .byte 0  ; Null terminator

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
    
    ; \ (backslash)
    .byte 0x01, 0x03, 0x06, 0x0C, 0x18  ; Backslash pattern
    
    ; = (equals)
    .byte 0x14, 0x14, 0x14, 0x14, 0x14  ; Equals pattern
    
    ; " (double quote)
    .byte 0x03, 0x00, 0x03, 0x00, 0x00  ; Double quote pattern
    
    ; ' (single quote)
    .byte 0x00, 0x03, 0x00, 0x00, 0x00  ; Single quote pattern
    
    ; ° (degree symbol)
    .byte 0x06, 0x09, 0x09, 0x06, 0x00  ; Degree symbol pattern

;================================================================
; Delay functions
;================================================================
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

delay_long:
    ; Longer delay for testing
    LDI   R23, 10
delay_long_outer:
    RCALL delay_ms
    DEC   R23
    BRNE  delay_long_outer
    RET
