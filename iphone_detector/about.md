# About Project

## Inspiration

Drones have become increasingly common in both civilian and emergency situations. While they provide many benefits, they can also introduce safety risks when operating near people or sensitive areas. We wanted to explore how modern AI running on an everyday smartphone could help improve situational awareness without requiring specialized equipment.

Our goal was to build a mobile application that can recognize potential drone activity using the sensors already available on an iPhone. We named the project **Vozhyk** ("Hedgehog" in Ukrainian), representing a small but vigilant defender that helps people stay aware of their surroundings.

## What it does

Vozhyk is an AI-powered iPhone application that detects possible drone activity by combining live camera AI with radio signal checks available on iOS.

The app continuously analyzes the live camera feed using Apple's Vision framework and Core ML. It runs a dual-model detection pipeline:

- A preserved YOLO model for general object detection, including autos, humans, trucks, buses, motorcycles, birds, and planes.
- A custom fine-tuned `plane_drone` model trained from our own reviewed drone video dataset.

This lets Vozhyk keep useful general scene awareness while improving detection of the specific drone/plane target class.

To help with long-distance detection, Vozhyk also includes automatic camera zoom. When the user holds the iPhone stable for a short moment, the app gradually zooms the real camera feed up to 5x, making small distant flying objects easier for the model to inspect. If the phone moves or turns again, zoom resets back to the default view.

Vozhyk can optionally estimate distance to detected humans, autos, and plane-drone targets. The app uses preset real-world object sizes and the current camera zoom factor to estimate the nearest supported detected object, then shows the result in the top-right corner of the live camera view.

At the same time, the application scans Bluetooth Low Energy devices and checks for known drone-related Wi-Fi network names that iOS makes available. By combining visual and radio observations, Vozhyk estimates the likelihood that a drone is nearby and displays a clear threat indicator:

- CLEAR
- POSSIBLE DRONE
- DRONE DETECTED

This multi-sensor approach provides users with improved situational awareness while running entirely on an iPhone.

## How we built it

The application was developed as a native SwiftUI iOS application.

Major technologies include:

- SwiftUI for the user interface
- AVFoundation for camera access and real camera zoom control
- Vision framework for real-time image processing
- Core ML with YOLO-based object detection
- A custom fine-tuned `plane_drone` Core ML model
- CoreBluetooth for BLE scanning
- Network framework for Wi-Fi identification where supported by iOS
- CoreMotion to detect when the iPhone is stable and trigger automatic zoom
- AVFoundation camera field-of-view and live zoom data for distance estimation
- Flask and OpenCV for the dataset preparation workflow
- OpenAI Codex to accelerate development, generate code, troubleshoot issues, fine-tune workflows, and iterate on implementation throughout the project

We also built a standalone Flask dataset preparation application. It allows us to upload drone videos, split them into frames, generate automatic mask proposals, manually redraw masks, approve or reject frames, and export YOLO-ready training datasets. Approved frames are accumulated into a persistent master dataset across multiple videos and Flask sessions, so future model improvements can continue from newly collected footage.

The iOS architecture separates camera processing, AI inference, radio scanning, settings, and user interface modules. The detection system also separates the custom drone model from the general YOLO model, which helps prevent a weak custom model from interfering with reliable general object detection.

## Challenges we ran into

Building a drone detector on iOS presented several challenges.

Apple intentionally limits access to low-level radio hardware for privacy and security reasons, so raw RF spectrum analysis is not available. We addressed this by combining the information that iOS *does* expose: Bluetooth devices, Wi-Fi identifiers, and computer vision.

Another challenge was detecting very small distant drones. A drone can be visible to a human but still too small for the camera model to classify confidently. To improve this, we added automatic real camera zoom that activates when the phone is stable and resets when the user moves.

Training data quality was also a major challenge. The first custom drone model was not good enough, so we built a dedicated dataset preparation tool, reviewed masks manually, trained a new `plane_drone` model, converted it to Core ML, integrated it into the iPhone app, and later fine-tuned it with additional reviewed data.

Finally, distinguishing drones from birds, airplanes, and other flying objects remains an active machine learning problem. We designed the application so improved custom models can be fine-tuned and integrated without changing the rest of the app architecture.

## Accomplishments that we're proud of

We're proud that Vozhyk demonstrates how multiple sensing techniques can work together inside a single mobile application.

Highlights include:

- Real-time iPhone camera detection
- On-device AI inference with Core ML
- Dual-model detection: general YOLO model plus custom fine-tuned `plane_drone` model
- Automatic camera zoom for long-distance object inspection
- Optional zoom-adjusted distance estimates for supported detected targets
- Bluetooth-based drone/controller signature detection
- Wi-Fi network identification where iOS allows it
- A simple threat dashboard designed for quick interpretation
- A standalone dataset preparation app for improving the model from new videos
- Manual mask review and correction for higher-quality training data
- A persistent master dataset workflow that supports future fine-tuning
- A modular architecture ready for future expansion

Most importantly, we built a working prototype that runs on standard iPhones without requiring specialized external hardware.

## What we learned

This project gave us hands-on experience combining computer vision, mobile AI, Bluetooth scanning, iOS system frameworks, model conversion, and dataset preparation into a single real-time application.

We learned that model quality depends heavily on the dataset preparation workflow. Simply training a model is not enough; reviewing frames, correcting masks, removing bad samples, and preserving class mappings are all critical for making the model usable inside a real app.

We also learned the practical limitations of mobile operating systems for RF detection and how combining multiple independent signals can provide more reliable results than relying on a single source.

Using OpenAI Codex significantly accelerated development by helping us prototype components, refactor code, build the Flask dataset tool, debug Core ML integration, update the iOS detection pipeline, and iterate through training and fine-tuning workflows throughout the hackathon.

## What's next for Vozhyk

Our roadmap includes:

- Collecting more real drone videos in different environments.
- Adding negative/background training frames such as empty sky, birds, normal planes, glare, and moving-camera scenes.
- Continuing to fine-tune the custom `plane_drone` model instead of restarting from generic weights.
- Improving detection confidence by intelligently fusing camera and radio observations.
- Expanding support for additional drone manufacturers and communication protocols.
- Reducing false positives in complex environments.
- Improving the automatic zoom behavior based on real field testing.
- Creating an iPhone Wi-Fi connection to a DOIT ESP32 DEVKIT V1.
- Sending detected drone position, confidence, zoom, and target data from the iPhone to the ESP32.
- Using the ESP32 with servos to control an external positioning ray toward the detected drone location.
- Mounting the iPhone on a mobile system where the phone acts as the visual "eyes" and the ESP32-controlled hardware responds when a drone is detected in the air.
- Adding offline event logging and optional location-based incident history.
- Integrating with external RF sensors for broader spectrum coverage where supported.

Ultimately, we envision Vozhyk becoming an accessible mobile safety tool that helps people better understand drone activity in their environment through responsible, privacy-conscious AI.
