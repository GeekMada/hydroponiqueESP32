#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <RTClib.h>

// Configuration du Wi-Fi
const char* ssid = "VotreSSID";
const char* password = "VotreMotDePasse";

#define DHTPIN 15       // Broche où est connecté le capteur DHT22
#define DHTTYPE DHT22  // Type de capteur DHT
#define RELAY_FAN 16    // Broche du relais pour le ventilateur
#define RELAY_HEATER 17 // Broche du relais pour le radiateur
#define RELAY_LIGHT 18  // Broche du relais pour l'éclairage

DHT dht(DHTPIN, DHTTYPE);
WebServer server(80);
RTC_DS3231 rtc;

float temperature = 0.0;
bool fanStatus = false;
bool heaterStatus = false;
bool lightStatus = false;

// Paramètres de croissance
enum GrowthStage {
  GERMINATION,
  GROWTH,
  FLOWERING
};

GrowthStage currentStage = GERMINATION;
unsigned long growthStartTime = 0;
bool isDay = true;

// Températures optimales pour chaque stade
const float TEMP_GERMINATION_MIN = 20.0;
const float TEMP_GERMINATION_MAX = 25.0;
const float TEMP_GROWTH_DAY_MIN = 18.0;
const float TEMP_GROWTH_DAY_MAX = 24.0;
const float TEMP_GROWTH_NIGHT_MIN = 15.0;
const float TEMP_GROWTH_NIGHT_MAX = 18.0;
const float TEMP_FLOWERING_DAY_MIN = 18.0;
const float TEMP_FLOWERING_DAY_MAX = 24.0;
const float TEMP_FLOWERING_NIGHT_MIN = 15.0;
const float TEMP_FLOWERING_NIGHT_MAX = 18.0;

// Durées des stades (en millisecondes)
const unsigned long GERMINATION_DURATION = 10L * 24 * 60 * 60 * 1000; // 10 jours
const unsigned long GROWTH_DURATION = 8L * 7 * 24 * 60 * 60 * 1000;   // 8 semaines
const unsigned long FLOWERING_DURATION = 8L * 7 * 24 * 60 * 60 * 1000; // 8 semaines

void setup() {
  Serial.begin(115200);
  dht.begin();
  if (!rtc.begin()) {
    Serial.println("Couldn't find RTC");
    while (1);
  }
  
  pinMode(RELAY_FAN, OUTPUT);
  pinMode(RELAY_HEATER, OUTPUT);
  pinMode(RELAY_LIGHT, OUTPUT);
  
  digitalWrite(RELAY_FAN, HIGH);
  digitalWrite(RELAY_HEATER, HIGH);
  digitalWrite(RELAY_LIGHT, HIGH);
  
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.println("Connexion au Wi-Fi...");
  }
  Serial.println("Connecté au Wi-Fi");
  Serial.print("Adresse IP: ");
  Serial.println(WiFi.localIP());

  server.on("/", HTTP_GET, handleRoot);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/control", HTTP_POST, handleControl);

  server.begin();
  Serial.println("Serveur HTTP démarré");

  growthStartTime = millis();
}

void loop() {
  server.handleClient();
  
  static unsigned long lastRead = 0;
  unsigned long currentMillis = millis();
  
  if (currentMillis - lastRead >= 60000) { // Vérification toutes les minutes
    lastRead = currentMillis;
    readTemperature();
    updateGrowthStage();
    updateDayNightCycle();
    controlDevices();
  }
}

void readTemperature() {
  float newTemp = dht.readTemperature();
  if (!isnan(newTemp)) {
    temperature = newTemp;
    Serial.print("Température: ");
    Serial.print(temperature);
    Serial.println(" °C");
  } else {
    Serial.println("Erreur de lecture du capteur DHT!");
  }
}

void updateGrowthStage() {
  unsigned long currentTime = millis();
  unsigned long elapsedTime = currentTime - growthStartTime;

  if (elapsedTime < GERMINATION_DURATION) {
    currentStage = GERMINATION;
  } else if (elapsedTime < GERMINATION_DURATION + GROWTH_DURATION) {
    currentStage = GROWTH;
  } else if (elapsedTime < GERMINATION_DURATION + GROWTH_DURATION + FLOWERING_DURATION) {
    currentStage = FLOWERING;
  } else {
    // Redémarrer le cycle
    growthStartTime = currentTime;
    currentStage = GERMINATION;
  }
}

void updateDayNightCycle() {
  DateTime now = rtc.now();
  isDay = (now.hour() >= 6 && now.hour() < 22); // Jour de 6h à 22h
  
  // Contrôle de l'éclairage
  if (isDay && !lightStatus) {
    digitalWrite(RELAY_LIGHT, LOW); // Allumer la lumière
    lightStatus = true;
  } else if (!isDay && lightStatus) {
    digitalWrite(RELAY_LIGHT, HIGH); // Éteindre la lumière
    lightStatus = false;
  }
}

void controlDevices() {
  float minTemp, maxTemp;

  switch (currentStage) {
    case GERMINATION:
      minTemp = TEMP_GERMINATION_MIN;
      maxTemp = TEMP_GERMINATION_MAX;
      break;
    case GROWTH:
    case FLOWERING:
      if (isDay) {
        minTemp = TEMP_GROWTH_DAY_MIN;
        maxTemp = TEMP_GROWTH_DAY_MAX;
      } else {
        minTemp = TEMP_GROWTH_NIGHT_MIN;
        maxTemp = TEMP_GROWTH_NIGHT_MAX;
      }
      break;
  }

  // Contrôle du ventilateur
  if (temperature > maxTemp) {
    digitalWrite(RELAY_FAN, LOW);  // Activer le ventilateur
    fanStatus = true;
  } else if (temperature < minTemp) {
    digitalWrite(RELAY_FAN, HIGH);  // Désactiver le ventilateur
    fanStatus = false;
  }

  // Contrôle du radiateur
  if (temperature < minTemp) {
    digitalWrite(RELAY_HEATER, LOW);  // Activer le radiateur
    heaterStatus = true;
  } else if (temperature > maxTemp) {
    digitalWrite(RELAY_HEATER, HIGH);  // Désactiver le radiateur
    heaterStatus = false;
  }
}

void handleRoot() {
  String html = "<html><body>";
  html += "<h1>Contrôle de Culture de Tomates ESP32</h1>";
  html += "<p>Température actuelle: " + String(temperature) + " °C</p>";
  html += "<p>Stade de croissance: " + String(getGrowthStageName(currentStage)) + "</p>";
  html += "<p>Période: " + String(isDay ? "Jour" : "Nuit") + "</p>";
  html += "<p>Ventilateur: " + String(fanStatus ? "ON" : "OFF") + "</p>";
  html += "<p>Radiateur: " + String(heaterStatus ? "ON" : "OFF") + "</p>";
  html += "<p>Éclairage: " + String(lightStatus ? "ON" : "OFF") + "</p>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

void handleStatus() {
  DynamicJsonDocument doc(512);
  doc["temperature"] = temperature;
  doc["growth_stage"] = getGrowthStageName(currentStage);
  doc["is_day"] = isDay;
  doc["fan"] = fanStatus;
  doc["heater"] = heaterStatus;
  doc["light"] = lightStatus;

  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleControl() {
  if (server.hasArg("plain")) {
    String body = server.arg("plain");
    DynamicJsonDocument doc(256);
    DeserializationError error = deserializeJson(doc, body);
    
    if (!error) {
      // Ici, vous pouvez ajouter des contrôles supplémentaires si nécessaire
      server.send(200, "application/json", "{\"status\":\"success\"}");
    } else {
      server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Invalid JSON\"}");
    }
  } else {
    server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"No body\"}");
  }
}

String getGrowthStageName(GrowthStage stage) {
  switch (stage) {
    case GERMINATION: return "Germination";
    case GROWTH: return "Croissance";
    case FLOWERING: return "Floraison et fructification";
    default: return "Inconnu";
  }
}
