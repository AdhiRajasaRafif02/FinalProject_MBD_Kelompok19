#include <Wire.h> 
#include <DHT.h>

// Konfigurasi DHT
#define DHTPIN 2      // Pin data DHT11 terhubung ke pin 2 Arduino
#define DHTTYPE DHT11 // Tipe sensor DHT11

DHT dht(DHTPIN, DHTTYPE);

void setup() {
  Wire.begin();      // Inisialisasi I2C sebagai Master
  dht.begin();       // Mulai sensor DHT
  Serial.begin(9600); // Mulai komunikasi Serial
}

void loop() {
  // Baca suhu dan kelembapan dari DHT11
  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature(); // Celsius

  // Cek apakah pembacaan valid
  if (isnan(humidity) || isnan(temperature)) {
    Serial.println("Gagal membaca dari sensor DHT11!");
    delay(2000);
    return;
  }

  // Tampilkan di Serial Monitor
  Serial.print("Suhu: ");
  Serial.print(temperature);
  Serial.print(" °C, Kelembapan: ");
  Serial.print(humidity);
  Serial.println(" %");

  // Kirim data suhu dan kelembapan ke Slave
  Wire.beginTransmission(9); // Alamat Slave = 9
  Wire.write((byte)temperature); // Kirim suhu (dibulatkan ke byte)
  Wire.write((byte)humidity);    // Kirim kelembapan (dibulatkan ke byte)
  Wire.endTransmission();        // Akhiri transmisi

  delay(2000); // Tunggu 2 detik sebelum kirim lagi
}
