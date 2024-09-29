# Système de contrôle automatisé pour la culture hydroponique de tomates avec ESP32

## Introduction

Ce projet présente un système automatisé utilisant un ESP32 pour gérer la température, l'éclairage et les différents stades de croissance des tomates en culture hydroponique. Il offre un contrôle précis de l'environnement pour optimiser la croissance et le rendement.

## Vue d'ensemble du système

Le système utilise les composants suivants :

1. ESP32 : Microcontrôleur avec Wi-Fi intégré
2. Capteur DHT22 : Pour mesurer la température
3. Module RTC (Real Time Clock) : Pour suivre le temps et gérer les cycles jour/nuit
4. Relais : Pour contrôler le ventilateur, le chauffage et l'éclairage
5. Serveur Web : Pour l'interface utilisateur et le contrôle à distance

## Fonctionnalités principales

1. Gestion automatique des stades de croissance (germination, croissance, floraison)
2. Contrôle de la température adapté à chaque stade et période (jour/nuit)
3. Gestion du cycle jour/nuit avec contrôle automatique de l'éclairage
4. Interface Web et API pour la surveillance et le contrôle à distance

## Code complet

Voici le code complet pour l'ESP32 :

```cpp
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
```

## Explication du code

### Initialisation et configuration (setup())

Cette fonction initialise tous les composants, établit la connexion Wi-Fi et configure le serveur web. Elle définit également les broches pour les relais et initialise le temps de début de croissance.

### Boucle principale (loop())

La boucle principale gère les requêtes du serveur web et effectue des vérifications périodiques (toutes les minutes) pour mettre à jour l'état du système. Elle appelle les fonctions suivantes :

- `readTemperature()` : Lit la température actuelle
- `updateGrowthStage()` : Met à jour le stade de croissance
- `updateDayNightCycle()` : Gère le cycle jour/nuit
- `controlDevices()` : Contrôle les dispositifs en fonction des conditions actuelles

### Gestion des stades de croissance (updateGrowthStage())

Cette fonction calcule le temps écoulé depuis le début de la culture et met à jour le stade de croissance en conséquence. Elle gère automatiquement la progression à travers les stades de germination, croissance et floraison.

### Contrôle du cycle jour/nuit (updateDayNightCycle())

Cette fonction utilise le module RTC pour déterminer s'il fait jour ou nuit et contrôle l'éclairage en conséquence. La période de jour est définie de 6h à 22h.

### Contrôle des dispositifs (controlDevices())

Cette fonction ajuste les températures cibles en fonction du stade de croissance et de la période (jour/nuit), puis contrôle le ventilateur et le chauffage pour maintenir ces températures.

### Interface Web et API (handleRoot(), handleStatus(), handleControl())

Ces fonctions gèrent l'interface web et l'API JSON, permettant aux utilisateurs de surveiller et de contrôler le système à distance.

## Configuration et utilisation

1. Remplacez "VotreSSID" et "VotreMotDePasse" par vos informations Wi-Fi.
2. Assurez-vous d'avoir connecté un module RTC (comme le DS3231) à votre ESP32.
3. Connectez le capteur DHT22 à la broche 15.
4. Connectez les relais aux broches suivantes :
   - Ventilateur : broche 16
   - Chauffage : broche 17
   - Éclairage : broche 18
5. Téléversez le code sur votre ESP32.
6. Ouvrez le moniteur série pour voir l'adresse IP attribuée à l'ESP32.
7. Accédez à l'interface web en utilisant cette adresse IP dans un navigateur.

## Conclusion

Ce système offre une solution automatisée pour la culture hydroponique des tomates, en gérant précisément la température et l'éclairage à chaque stade de croissance. Il peut être facilement adapté à d'autres types de cultures en ajustant les paramètres de température et les durées des stades de croissance.

Pour les développeurs souhaitant étendre ce système, des améliorations possibles incluent :

1. L'ajout de capteurs d'humidité et de CO2
2. L'intégration d'un système de gestion des nutriments
3. La mise en place d'un système de journalisation des données pour le suivi à long terme
4. L'ajout d'alertes par e-mail ou SMS en cas de conditions anormales
5. L'intégration avec des plateformes domotiques comme Home Assistant ou OpenHAB

N'hésitez pas à adapter et à améliorer ce code selon vos besoins spécifiques !
