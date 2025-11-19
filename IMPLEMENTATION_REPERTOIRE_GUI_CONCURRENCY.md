# Implementation: Repertoire GUI Concurrency Fix
_Date: 2025-11-18_

## What Was Fixed

The Repertoire tab in MacStudioServerSimulator was processing only 6 songs and then stalling, failing to complete the full 90-song analysis queue.

## Root Cause

The issue was caused by fragile Swift concurrency architecture:
- Unstructured `Task` created directly in SwiftUI view
- Multiple `MainActor.run` calls scattered throughout analysis logic
- Complex nested task groups with timeout wrappers
- View lifecycle issues potentially cancelling tasks mid-execution

## Solution Implemented

Implemented a clean **@MainActor controller pattern** following Apple's Swift concurrency best practices:

### 1. New File: `RepertoireAnalysisController.swift`

Created a dedicated `@MainActor` controller class that:
- **Owns all state**: `rows`, `spotifyTracks`, `isAnalyzing`, `alertMessage`
- **Manages task lifecycle**: Stores and cancels `analysisTask` properly
- **Implements clean batching**: Processes songs in batches of 6 using `withTaskGroup`
- **Provides logging**: Console output for debugging batch progress

Key features:
- `startAnalysis()`: Main entry point that ensures server is running, then calls `runAnalysisBatches()`
- `runAnalysisBatches()`: Loops through all songs in batches of 6, checking for cancellation between batches
- `analyzeRow(at:)`: Simple per-row analysis without complex timeout wrappers
- All data loading and helper methods moved from view

### 2. Refactored: `ServerManagementTestsTab.swift`

Simplified `RepertoireComparisonTab` view to:
- Use `@StateObject var controller: RepertoireAnalysisController`
- Bind UI to controller's published properties
- Delegate all actions to controller methods
- Removed all analysis logic, state management, and helper functions

The view is now a thin wrapper that:
- Displays UI bound to controller state
- Calls `Task { await controller.startAnalysis() }` on button press
- Handles alerts via controller's `alertMessage` property

### 3. Updated: Xcode Project Configuration

Added `RepertoireAnalysisController.swift` to:
- PBXBuildFile section (with ID `REPC00000000000000000001`)
- PBXFileReference section (with ID `REPC00000000000000000002`)
- PBXGroup (MacStudioServerSimulator file list)
- PBXSourcesBuildPhase (build sources)

## Technical Details

### Batch Processing Logic

```swift
func runAnalysisBatches() async {
    let indices = Array(rows.indices)
    let batchSize = 6
    var start = 0
    
    while start < indices.count {
        if Task.isCancelled { break }
        
        let end = min(start + batchSize, indices.count)
        let batch = Array(indices[start..<end])
        
        // Process batch of 6 concurrently
        await withTaskGroup(of: Void.self) { group in
            for index in batch {
                group.addTask { [weak self] in
                    await self?.analyzeRow(at: index)
                }
            }
            await group.waitForAll()
        }
        
        start = end
    }
}
```

### Benefits

1. **Proper concurrency**: `@MainActor` isolation ensures thread-safe state mutations
2. **Clean separation**: View handles UI, controller handles business logic
3. **Cancellation support**: Stores task handle, checks `Task.isCancelled` between batches
4. **Simplified error handling**: Removed complex timeout wrappers, rely on server timeouts
5. **Debugging**: Console logging shows batch progress

## Expected Behavior

✅ **All 90 songs processed** without stalling  
✅ **6 concurrent analyses** at any given time  
✅ **Accurate UI state**: Rows show Pending → Running → Done/Failed  
✅ **Spinner visibility**: `isAnalyzing` correctly reflects analysis state  
✅ **Error resilience**: Failed songs don't block remaining queue  

## Testing Recommendations

1. **Full repertoire run**: Load 90-preview dataset, click Analyze, verify all songs complete
2. **Batch observation**: Watch console logs showing batches 1-15 completing
3. **UI responsiveness**: Confirm spinner appears/disappears correctly
4. **Partial failure**: Corrupt a few files, verify analysis continues for remaining songs
5. **Re-run test**: Run analysis twice without restarting app

## Alignment with Python Tests

This implementation matches the concurrency model used in:
- `tools/test_analysis_suite.py`: `ThreadPoolExecutor(max_workers=6)`
- `run_test.sh` (Test A/C): 6 concurrent requests to server
- Backend server design: Expects client-side parallelism with small process pool

## Files Changed

1. ✅ **Created**: `MacStudioServerSimulator/MacStudioServerSimulator/RepertoireAnalysisController.swift`
2. ✅ **Modified**: `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementTestsTab.swift`
3. ✅ **Modified**: `MacStudioServerSimulator/MacStudioServerSimulator.xcodeproj/project.pbxproj`

## Next Steps

To verify the fix works:

1. Open `MacStudioServerSimulator.xcworkspace` in Xcode
2. Build and run the app (Cmd+R)
3. Navigate to Tests tab → Repertoire
4. Load default dataset (should auto-load 90 previews)
5. Click "Analyze with Latest Algorithms"
6. Watch console for batch progress logs
7. Verify all 90 songs complete without stalling

If issues persist, check:
- Xcode console for error messages
- Python server logs at `/tmp/essentia_server.log`
- Network connectivity to localhost:5002
