# Mac Studio Server Simulator - Xcode Project

## Overview

This Xcode project allows you to test the Mac Studio Audio Analysis Server from the iOS Simulator or a real iOS device.

## Features

- Test server connection and status
- Analyze audio from URLs
- View Phase 1 advanced analysis features:
  - Time signature detection
  - Mood and valence estimation
  - Loudness and dynamic range
  - Silence detection
- View server statistics and cache performance

## Prerequisites

1. **Mac with Xcode** (Xcode 15.0 or later recommended)
2. **Mac Studio Server Running** - The Python server must be running:
   ```bash
   cd backend/
   python3 analyze_server.py
   ```
3. **iOS 17.0+** for the simulator

## Setup Instructions

### 1. Open the Project

```bash
cd EssentiaServer
open MacStudioServerSimulator.xcworkspace
```

Or double-click `MacStudioServerSimulator.xcworkspace` in Finder.

### 2. Start the Python Server

Before running the simulator, start the backend server:

```bash
cd backend/
python3 analyze_server.py
```

You should see:
```
🎵 Mac Studio Audio Analysis Server
📡 Listening on http://127.0.0.1:5050
```

### 3. Run in Simulator

1. In Xcode, select a simulator (iPhone 15 Pro recommended)
2. Click the Play button or press `Cmd+R`
3. The app will launch in the simulator

### 4. Test the Connection

1. In the app, tap "Check Status"
2. If the server is running, you'll see a green "Connected" indicator
3. View the server statistics below

## Using the Simulator

### Test Audio Analysis

1. Navigate to "Audio Analysis Test"
2. Enter a preview URL (or use the default test URL)
3. Enter song title and artist
4. Tap "Analyze Audio"
5. View the results including:
   - Core metrics (BPM, key, energy, etc.)
   - Phase 1 features (mood, loudness, silence ratio, etc.)

### View Phase 1 Features

1. Navigate to "Phase 1 Features Test"
2. See descriptions of all Phase 1 capabilities
3. Test different scenarios

## Configuration

### Change Server Port

If your server is running on a different port:

1. In the app, change the port number in the "Port" field
2. Tap "Check Status" to reconnect

### Use on Real Device

To test with a real iPhone/iPad:

1. Ensure your device and Mac are on the same network
2. Update `MacStudioServerManager.swift`:
   ```swift
   private var baseURL: String {
       #if targetEnvironment(simulator)
       return "http://127.0.0.1:\(serverPort)"
       #else
       return "http://YOUR-MAC-IP:\(serverPort)"  // Change this
       #endif
   }
   ```
3. Replace `YOUR-MAC-IP` with your Mac's local IP address
4. Build and run on your device

## Project Structure

```
MacStudioServerSimulator/
├── MacStudioServerSimulator.xcworkspace/     # Xcode workspace
├── MacStudioServerSimulator/
│   ├── MacStudioServerSimulator.xcodeproj/   # Xcode project
│   └── MacStudioServerSimulator/             # Source code
│       ├── MacStudioServerSimulatorApp.swift # App entry point
│       ├── ContentView.swift                 # Main view
│       ├── ServerTestView.swift              # Audio analysis test
│       ├── Models/
│       │   └── ServerModels.swift            # Data models
│       └── Services/
│           └── MacStudioServerManager.swift  # API client
```

## API Endpoints Tested

- `GET /health` - Server health check
- `GET /stats` - Server statistics
- `POST /analyze` - Analyze audio from URL
- `POST /analyze_data` - Analyze audio data directly

## Example Test Workflow

1. **Start the server** on your Mac
2. **Open the Xcode project**
3. **Run in simulator**
4. **Check server status** - Verify connection
5. **Test audio analysis** with a sample URL:
   - Use an Apple Music preview URL
   - View BPM, key, energy, etc.
   - Check Phase 1 features (mood, loudness, etc.)
6. **View server stats** - See cache performance

## Troubleshooting

### "Cannot connect to server"

- Ensure the Python server is running: `python3 analyze_server.py`
- Check the port number (default: 5050)
- If using a real device, verify network connectivity

### "Invalid API response"

- Server might be outdated - pull latest changes
- Check server logs for errors

### Xcode Build Errors

- Clean build folder: `Cmd+Shift+K`
- Rebuild: `Cmd+B`
- Check iOS deployment target is 17.0+

## Phase 1 Features in the Simulator

The simulator fully supports testing all Phase 1 features:

1. **Time Signature** - See detected time signature (3/4, 4/4, etc.)
2. **Valence** - Emotional positivity score (0-1)
3. **Mood** - Category (energetic, happy, neutral, tense, melancholic)
4. **Loudness** - LUFS-like measurement in dB
5. **Dynamic Range** - Difference between loud and quiet (dB)
6. **Silence Ratio** - Percentage of silent frames

## Performance Testing

Use the simulator to:
- Test cache performance (watch cache hit rate increase)
- Verify analysis speed (should be <5 seconds)
- Test concurrent requests
- Monitor server statistics

## Next Steps

After testing in the simulator:
- Test on a real iOS device
- Integrate into your main iOS app
- Test Phase 2 features when available
- Build production workflows

## Support

For issues or questions:
1. Check the server logs: `backend/~/Music/AudioAnalysisCache/server.log`
2. Review the main documentation: `backend/README.md`
3. Check Phase 1 documentation: `backend/PHASE1_FEATURES.md`

---

**Happy Testing! 🎵**
