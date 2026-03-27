# Free PT Consultation

## Project Layout

```text
free-pt-consultation/
├── ios/
│   └── VoilaWinnerApp/
│       ├── VoilaWinnerApp.xcodeproj
│       └── VoilaWinnerApp/
│           ├── ContentView.swift
│           ├── Info.plist
│           └── VoilaWinnerAppApp.swift
├── python/
│   ├── pyproject.toml
│   ├── src/
│   │   ├── data_ingestion/
│   │   │   ├── health_stats.py
│   │   │   ├── models.py
│   │   │   ├── router.py
│   │   │   └── sources/
│   │   │       ├── apple_health.py
│   │   │       ├── garmin.py
│   │   │       ├── intake_forms.py
│   │   │       └── renpho.py
│   │   ├── research/
│   │   │   ├── extract.py
│   │   │   └── summarize.py
│   │   └── main.py
│   └── tests/
│       └── test_router.py
└── README.md
```

## Python data pipeline (research + source-specific inputs)

- `data_ingestion/sources/apple_health.py`: Apple Health normalization logic.
- `data_ingestion/sources/garmin.py`: Garmin normalization logic.
- `data_ingestion/sources/renpho.py`: Renpho smart scale normalization logic.
- `data_ingestion/sources/intake_forms.py`: Intake form normalization logic.
- `data_ingestion/router.py`: source router so each source is handled explicitly.
- `data_ingestion/health_stats.py`: health metric calculations from normalized records.
- `research/extract.py`: PDF text extraction for research papers.
- `research/summarize.py`: basic summary helper placeholder.

### Run locally

```bash
cd python
python -m venv .venv
source .venv/bin/activate
pip install -e .
pytest
python src/main.py
```

## iOS app

`ios/VoilaWinnerApp` is a SwiftUI iOS app that reads activity/workout data from **Apple Health (HealthKit)** and shows a lightweight training dashboard.

### Install to your iPhone

1. Open `ios/VoilaWinnerApp/VoilaWinnerApp.xcodeproj` in Xcode (macOS).
2. Set your Apple Developer Team in **Signing & Capabilities**.
3. In the target, confirm **HealthKit** capability is enabled.
4. Plug your iPhone into your Mac (or use wireless debugging).
5. Select your iPhone as the run destination.
6. Press **Run** in Xcode; it will build and install the app on your phone.
7. On first launch, allow Health access permissions when prompted.

### HealthKit notes

- The app requests read access for steps, active energy, and workouts.
- Data comes from the iPhone Health app (which includes Apple Watch workouts synced via Apple Health).
- If no data appears, open **Health app → Browse** and ensure those categories have recent entries.

> Note: to distribute beyond your own device, use TestFlight/App Store via an Apple Developer account.
