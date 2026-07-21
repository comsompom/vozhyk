#include <Arduino.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <WebServer.h>
#include <WiFi.h>
#include <math.h>

namespace {

constexpr const char *AP_SSID = "Vozhyk-Robot";
constexpr const char *AP_PASSWORD = "vozhyk-esp32";
constexpr uint16_t HTTP_PORT = 80;
constexpr uint32_t LOG_INTERVAL_MS = 5000;
constexpr uint32_t SCAN_STEP_INTERVAL_MS = 2000;
constexpr int SERVO_MIN_US = 500;
constexpr int SERVO_MAX_US = 2500;
constexpr int MAIN_PLATFORM_SERVO_PIN = 25;
constexpr int RAY_X_SERVO_PIN = 26;
constexpr int RAY_Y_SERVO_PIN = 27;
constexpr int MAIN_SCAN_MIN_DEGREES = 0;
constexpr int MAIN_SCAN_MAX_DEGREES = 180;
constexpr int MAIN_SCAN_STEP_DEGREES = 5;
constexpr int RAY_X_MIN_DEGREES = 0;
constexpr int RAY_X_MAX_DEGREES = 180;
constexpr int RAY_Y_MIN_DEGREES = 0;
constexpr int RAY_Y_MAX_DEGREES = 180;
constexpr int RAY_CENTER_DEGREES = 90;

WebServer server(HTTP_PORT);
Servo mainPlatformServo;
Servo rayXServo;
Servo rayYServo;

struct IPhoneState {
  bool connected = false;
  String deviceName = "unknown";
  IPAddress remoteIp;
  uint32_t connectedAtMs = 0;
  uint32_t lastSeenMs = 0;
};

struct TargetPacket {
  bool valid = false;
  String objectName = "unknown";
  float screenX = 0.0f;
  float screenY = 0.0f;
  double latitude = 0.0;
  double longitude = 0.0;
  float altitudeMeters = 0.0f;
  float distanceMeters = 0.0f;
  float confidence = 0.0f;
  uint32_t receivedAtMs = 0;
};

IPhoneState iphone;
TargetPacket lastTarget;
uint32_t lastHeartbeatLogMs = 0;
bool scanEnabled = true;
int mainPlatformAngle = MAIN_SCAN_MIN_DEGREES;
int mainPlatformDirection = 1;
int rayXAngle = RAY_CENTER_DEGREES;
int rayYAngle = RAY_CENTER_DEGREES;
uint32_t lastScanStepMs = 0;

void addCorsHeaders() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
}

void sendJson(int statusCode, const String &json) {
  addCorsHeaders();
  server.send(statusCode, "application/json", json);
}

void sendOptions() {
  addCorsHeaders();
  server.send(204, "text/plain", "");
}

String requestBody() {
  if (!server.hasArg("plain")) {
    return "";
  }
  return server.arg("plain");
}

void logRequest(const char *endpoint) {
  Serial.printf(
      "[HTTP] %s from %s, body=%u bytes\n",
      endpoint,
      server.client().remoteIP().toString().c_str(),
      requestBody().length());
}

bool parseJsonBody(JsonDocument &doc) {
  const String body = requestBody();
  if (body.isEmpty()) {
    sendJson(400, "{\"ok\":false,\"error\":\"missing JSON body\"}");
    return false;
  }

  DeserializationError error = deserializeJson(doc, body);
  if (error) {
    Serial.printf("[HTTP] JSON parse error: %s\n", error.c_str());
    sendJson(400, "{\"ok\":false,\"error\":\"invalid JSON\"}");
    return false;
  }

  return true;
}

float jsonFloat(JsonVariantConst root, const char *flatKey, const char *objectKey, const char *nestedKey, float fallback = 0.0f) {
  if (!root[flatKey].isNull()) {
    return root[flatKey].as<float>();
  }
  if (!root[objectKey][nestedKey].isNull()) {
    return root[objectKey][nestedKey].as<float>();
  }
  return fallback;
}

double jsonDouble(JsonVariantConst root, const char *flatKey, const char *objectKey, const char *nestedKey, double fallback = 0.0) {
  if (!root[flatKey].isNull()) {
    return root[flatKey].as<double>();
  }
  if (!root[objectKey][nestedKey].isNull()) {
    return root[objectKey][nestedKey].as<double>();
  }
  return fallback;
}

String jsonString(JsonVariantConst root, const char *flatKey, const char *objectKey, const char *nestedKey, const char *fallback) {
  if (!root[flatKey].isNull()) {
    return root[flatKey].as<const char *>();
  }
  if (!root[objectKey][nestedKey].isNull()) {
    return root[objectKey][nestedKey].as<const char *>();
  }
  return fallback;
}

float clampUnit(float value) {
  if (!isfinite(value)) {
    return 0.5f;
  }
  return min(1.0f, max(0.0f, value));
}

int clampAngle(int value, int minDegrees, int maxDegrees) {
  return min(maxDegrees, max(minDegrees, value));
}

int screenCoordinateToServoAngle(float normalizedValue, int minDegrees, int maxDegrees, bool invert = false) {
  const float value = invert ? 1.0f - clampUnit(normalizedValue) : clampUnit(normalizedValue);
  return clampAngle(
      static_cast<int>(roundf(minDegrees + value * (maxDegrees - minDegrees))),
      minDegrees,
      maxDegrees);
}

void writeMainPlatformServo(int angle) {
  mainPlatformAngle = clampAngle(angle, MAIN_SCAN_MIN_DEGREES, MAIN_SCAN_MAX_DEGREES);
  mainPlatformServo.write(mainPlatformAngle);
}

void writeRayServos(int xAngle, int yAngle) {
  rayXAngle = clampAngle(xAngle, RAY_X_MIN_DEGREES, RAY_X_MAX_DEGREES);
  rayYAngle = clampAngle(yAngle, RAY_Y_MIN_DEGREES, RAY_Y_MAX_DEGREES);
  rayXServo.write(rayXAngle);
  rayYServo.write(rayYAngle);
}

void aimRayAtScreenPoint(float screenX, float screenY) {
  const int xAngle = screenCoordinateToServoAngle(screenX, RAY_X_MIN_DEGREES, RAY_X_MAX_DEGREES);
  const int yAngle = screenCoordinateToServoAngle(screenY, RAY_Y_MIN_DEGREES, RAY_Y_MAX_DEGREES, true);
  writeRayServos(xAngle, yAngle);

  Serial.printf(
      "[SERVO] Ray target screen=(%.4f, %.4f) -> x=%d deg y=%d deg\n",
      screenX,
      screenY,
      rayXAngle,
      rayYAngle);
}

void markIPhoneSeen(const String &deviceName) {
  iphone.connected = true;
  iphone.deviceName = deviceName.isEmpty() ? "unknown" : deviceName;
  iphone.remoteIp = server.client().remoteIP();
  iphone.lastSeenMs = millis();
  if (iphone.connectedAtMs == 0) {
    iphone.connectedAtMs = iphone.lastSeenMs;
  }
}

void handleStatus() {
  JsonDocument doc;
  doc["ok"] = true;
  doc["station"] = "vozhyk-esp32";
  doc["ap_ssid"] = AP_SSID;
  doc["ip"] = WiFi.softAPIP().toString();
  doc["uptime_ms"] = millis();
  doc["iphone"]["connected"] = iphone.connected;
  doc["iphone"]["device"] = iphone.deviceName;
  doc["iphone"]["remote_ip"] = iphone.remoteIp.toString();
  doc["iphone"]["last_seen_ms"] = iphone.lastSeenMs;
  doc["target"]["valid"] = lastTarget.valid;
  doc["target"]["object_name"] = lastTarget.objectName;
  doc["target"]["screen_x"] = lastTarget.screenX;
  doc["target"]["screen_y"] = lastTarget.screenY;
  doc["target"]["latitude"] = lastTarget.latitude;
  doc["target"]["longitude"] = lastTarget.longitude;
  doc["target"]["altitude_m"] = lastTarget.altitudeMeters;
  doc["target"]["distance_m"] = lastTarget.distanceMeters;
  doc["target"]["confidence"] = lastTarget.confidence;
  doc["target"]["received_at_ms"] = lastTarget.receivedAtMs;
  doc["servos"]["main_platform_pin"] = MAIN_PLATFORM_SERVO_PIN;
  doc["servos"]["ray_x_pin"] = RAY_X_SERVO_PIN;
  doc["servos"]["ray_y_pin"] = RAY_Y_SERVO_PIN;
  doc["servos"]["scan_enabled"] = scanEnabled;
  doc["servos"]["main_platform_angle"] = mainPlatformAngle;
  doc["servos"]["ray_x_angle"] = rayXAngle;
  doc["servos"]["ray_y_angle"] = rayYAngle;

  String response;
  serializeJson(doc, response);
  sendJson(200, response);
}

void handleIPhoneConnect() {
  logRequest("/iphone/connect");

  JsonDocument doc;
  if (!parseJsonBody(doc)) {
    return;
  }

  const String deviceName = jsonString(doc.as<JsonVariantConst>(), "device", "iphone", "device", "iphone");
  markIPhoneSeen(deviceName);

  Serial.printf(
      "[IPHONE] Connected device=%s remote_ip=%s uptime_ms=%lu\n",
      iphone.deviceName.c_str(),
      iphone.remoteIp.toString().c_str(),
      static_cast<unsigned long>(millis()));

  sendJson(200, "{\"ok\":true,\"message\":\"iphone connected\"}");
}

void handleTarget() {
  logRequest("/target");

  JsonDocument doc;
  if (!parseJsonBody(doc)) {
    return;
  }

  JsonVariantConst root = doc.as<JsonVariantConst>();
  markIPhoneSeen(jsonString(root, "device", "iphone", "device", iphone.deviceName.c_str()));

  TargetPacket packet;
  packet.valid = true;
  packet.objectName = jsonString(root, "object_name", "object", "name", "unknown");
  packet.screenX = jsonFloat(root, "screen_x", "screen", "x", jsonFloat(root, "cx", "screen", "cx"));
  packet.screenY = jsonFloat(root, "screen_y", "screen", "y", jsonFloat(root, "cy", "screen", "cy"));
  packet.latitude = jsonDouble(root, "latitude", "object", "latitude");
  packet.longitude = jsonDouble(root, "longitude", "object", "longitude");
  packet.altitudeMeters = jsonFloat(root, "altitude_m", "object", "altitude_m", jsonFloat(root, "altitude", "object", "altitude"));
  packet.distanceMeters = jsonFloat(root, "distance_m", "object", "distance_m", jsonFloat(root, "distance", "object", "distance"));
  packet.confidence = jsonFloat(root, "confidence", "object", "confidence");
  packet.receivedAtMs = millis();

  lastTarget = packet;

  Serial.println("[TARGET] Received object target");
  Serial.printf("  object=%s confidence=%.3f\n", lastTarget.objectName.c_str(), lastTarget.confidence);
  Serial.printf("  screen=(%.4f, %.4f)\n", lastTarget.screenX, lastTarget.screenY);
  Serial.printf("  gps=(%.7f, %.7f) altitude=%.2f m distance=%.2f m\n",
                lastTarget.latitude,
                lastTarget.longitude,
                lastTarget.altitudeMeters,
                lastTarget.distanceMeters);
  Serial.printf("  iphone=%s remote_ip=%s received_at_ms=%lu\n",
                iphone.deviceName.c_str(),
                iphone.remoteIp.toString().c_str(),
                static_cast<unsigned long>(lastTarget.receivedAtMs));

  aimRayAtScreenPoint(lastTarget.screenX, lastTarget.screenY);

  sendJson(200, "{\"ok\":true,\"message\":\"target accepted\"}");
}

void handleScanStart() {
  scanEnabled = true;
  lastScanStepMs = millis();
  Serial.println("[SERVO] Main platform scan started");
  sendJson(200, "{\"ok\":true,\"scan_enabled\":true}");
}

void handleScanStop() {
  scanEnabled = false;
  Serial.println("[SERVO] Main platform scan stopped");
  sendJson(200, "{\"ok\":true,\"scan_enabled\":false}");
}

void handleNotFound() {
  addCorsHeaders();
  server.send(404, "application/json", "{\"ok\":false,\"error\":\"not found\"}");
}

void configureHttpApi() {
  server.on("/", HTTP_GET, handleStatus);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/iphone/connect", HTTP_OPTIONS, sendOptions);
  server.on("/iphone/connect", HTTP_POST, handleIPhoneConnect);
  server.on("/target", HTTP_OPTIONS, sendOptions);
  server.on("/target", HTTP_POST, handleTarget);
  server.on("/scan/start", HTTP_OPTIONS, sendOptions);
  server.on("/scan/start", HTTP_POST, handleScanStart);
  server.on("/scan/stop", HTTP_OPTIONS, sendOptions);
  server.on("/scan/stop", HTTP_POST, handleScanStop);
  server.onNotFound(handleNotFound);
  server.begin();
}

void configureServos() {
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);

  mainPlatformServo.setPeriodHertz(50);
  rayXServo.setPeriodHertz(50);
  rayYServo.setPeriodHertz(50);

  mainPlatformServo.attach(MAIN_PLATFORM_SERVO_PIN, SERVO_MIN_US, SERVO_MAX_US);
  rayXServo.attach(RAY_X_SERVO_PIN, SERVO_MIN_US, SERVO_MAX_US);
  rayYServo.attach(RAY_Y_SERVO_PIN, SERVO_MIN_US, SERVO_MAX_US);

  writeMainPlatformServo(mainPlatformAngle);
  writeRayServos(rayXAngle, rayYAngle);

  Serial.printf("[SERVO] Main platform signal pin=%d angle=%d deg\n", MAIN_PLATFORM_SERVO_PIN, mainPlatformAngle);
  Serial.printf("[SERVO] Ray X signal pin=%d angle=%d deg\n", RAY_X_SERVO_PIN, rayXAngle);
  Serial.printf("[SERVO] Ray Y signal pin=%d angle=%d deg\n", RAY_Y_SERVO_PIN, rayYAngle);
  Serial.println("[SERVO] Use separate servo power. Connect ESP32 GND to servo battery GND.");
}

void startAccessPoint() {
  WiFi.mode(WIFI_AP);
  const bool ok = WiFi.softAP(AP_SSID, AP_PASSWORD);

  Serial.println();
  Serial.println("[BOOT] Vozhyk ESP32 robot station connector");
  Serial.printf("[WIFI] AP start: %s\n", ok ? "ok" : "failed");
  Serial.printf("[WIFI] SSID: %s\n", AP_SSID);
  Serial.printf("[WIFI] Password: %s\n", AP_PASSWORD);
  Serial.printf("[WIFI] IP: %s\n", WiFi.softAPIP().toString().c_str());
  Serial.printf("[HTTP] Listening on http://%s:%u\n", WiFi.softAPIP().toString().c_str(), HTTP_PORT);
}

void logHeartbeat() {
  const uint32_t now = millis();
  if (now - lastHeartbeatLogMs < LOG_INTERVAL_MS) {
    return;
  }
  lastHeartbeatLogMs = now;

  Serial.printf(
      "[STATUS] uptime=%lu ms clients=%d iphone=%s last_target=%s\n",
      static_cast<unsigned long>(now),
      WiFi.softAPgetStationNum(),
      iphone.connected ? iphone.deviceName.c_str() : "not-connected",
      lastTarget.valid ? lastTarget.objectName.c_str() : "none");
}

void updateMainPlatformScan() {
  if (!scanEnabled) {
    return;
  }

  const uint32_t now = millis();
  if (now - lastScanStepMs < SCAN_STEP_INTERVAL_MS) {
    return;
  }
  lastScanStepMs = now;

  int nextAngle = mainPlatformAngle + mainPlatformDirection * MAIN_SCAN_STEP_DEGREES;
  if (nextAngle >= MAIN_SCAN_MAX_DEGREES) {
    nextAngle = MAIN_SCAN_MAX_DEGREES;
    mainPlatformDirection = -1;
  } else if (nextAngle <= MAIN_SCAN_MIN_DEGREES) {
    nextAngle = MAIN_SCAN_MIN_DEGREES;
    mainPlatformDirection = 1;
  }

  writeMainPlatformServo(nextAngle);
  Serial.printf("[SERVO] Main platform scan angle=%d deg direction=%d\n", mainPlatformAngle, mainPlatformDirection);
}

} // namespace

void setup() {
  Serial.begin(115200);
  delay(600);

  startAccessPoint();
  configureServos();
  configureHttpApi();

  Serial.println("[READY] Connect iPhone to Vozhyk-Robot Wi-Fi and POST /iphone/connect or /target.");
}

void loop() {
  server.handleClient();
  updateMainPlatformScan();
  logHeartbeat();
}
