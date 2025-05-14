#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1  // Reset pin tidak digunakan pada modul I2C
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

byte temperature = 0;
byte humidity = 0;

const int buzzerPin = 4;
const int ledMerahPin = 5;

void setup() {
  Wire.begin(9);
  Wire.onReceive(receiveEvent);

  pinMode(buzzerPin, OUTPUT);
  pinMode(ledMerahPin, OUTPUT);
  digitalWrite(buzzerPin, LOW);
  digitalWrite(ledMerahPin, LOW);

  Serial.begin(9600);

  // Inisialisasi OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("Gagal inisialisasi OLED"));
    while (true);
  }
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("Menunggu data...");
  display.display();
}

void loop() {
  // Tampilkan di Serial
  Serial.print("Suhu: ");
  Serial.print(temperature);
  Serial.print(" °C, Kelembapan: ");
  Serial.print(humidity);
  Serial.println(" %");

  // Cek kondisi dan atur LED/buzzer
  bool kondisiBahaya = temperature >= 30;

  digitalWrite(buzzerPin, kondisiBahaya ? HIGH : LOW);
  digitalWrite(ledMerahPin, kondisiBahaya ? HIGH : LOW);

  // Tampilkan di OLED
  display.clearDisplay();
  display.setCursor(0, 0);
  display.print("Suhu: ");
  display.print(temperature);
  display.println(" C");

  display.print("Kelembapan: ");
  display.print(humidity);
  display.println(" %");

  display.print("Status: ");
  if (kondisiBahaya) {
    display.println("PANAS!");
    display.println("LED & Buzzer AKTIF");
  } else {
    display.println("Normal");
    display.println("LED & Buzzer OFF");
  }

  display.display();

  delay(1000);
}

void receiveEvent(int howMany) {
  if (howMany >= 2) {
    temperature = Wire.read();
    humidity = Wire.read();
  }
}
