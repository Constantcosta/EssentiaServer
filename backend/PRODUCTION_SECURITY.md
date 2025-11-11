# 🔒 Production Security Setup Guide

## Overview

Your server now has **production-ready security** with:
- ✅ API Key Authentication
- ✅ Rate Limiting (60 requests/minute per key)
- ✅ Daily Usage Quotas
- ✅ Usage Tracking & Analytics
- ✅ Two-mode operation (Development/Production)

---

## 🚀 Quick Start

### Development Mode (Default - localhost only)
```bash
# Current setup - no authentication needed, localhost only
python3 analyze_server.py
```

### Production Mode (Remote access with authentication)
```bash
# Enable remote access with security
export PRODUCTION_MODE=true
python3 analyze_server.py

# Or run on specific IP
export PRODUCTION_MODE=true
python3 -c "
from analyze_server import app, init_db
init_db()
app.run(host='0.0.0.0', port=5050, debug=False)
"
```

---

## 🔑 Managing API Keys

### Create Your First API Key
```bash
# For your personal devices (unlimited)
python3 manage_api_keys.py create "Costas iPhone" costas@email.com 0

# Output shows your API key - SAVE IT!
# Example: xK7mP9nR4tL2wQ8vH5jN3bF6gY1aZ0cV
```

### Beta Testers
```bash
# Limited to 1000 requests per day
python3 manage_api_keys.py create "Beta Tester - John" john@test.com 1000
python3 manage_api_keys.py create "Beta Tester - Sarah" sarah@test.com 1000
```

### Commercial Clients
```bash
# Premium tier: 10,000 requests/day
python3 manage_api_keys.py create "DJ Pro License" client@djapp.com 10000

# Enterprise tier: 100,000 requests/day
python3 manage_api_keys.py create "Enterprise Client" enterprise@company.com 100000
```

### View All Keys
```bash
python3 manage_api_keys.py list
```

### View Key Details & Usage
```bash
python3 manage_api_keys.py show 1
```

### Manage Keys
```bash
# Temporarily disable a key
python3 manage_api_keys.py deactivate 2

# Re-enable a key
python3 manage_api_keys.py activate 2

# Change daily limit
python3 manage_api_keys.py limit 3 5000

# Delete a key (permanent!)
python3 manage_api_keys.py delete 4
```

---

## 📱 Using API Keys in Your App

### Swift/iOS Example
```swift
func analyzeAudio(audioData: Data, title: String, artist: String) async throws -> AnalysisResult {
    var request = URLRequest(url: URL(string: "https://your-server.com:5050/analyze_data")!)
    request.httpMethod = "POST"
    request.httpBody = audioData
    
    // Add API key to request
    request.setValue("xK7mP9nR4tL2wQ8vH5jN3bF6gY1aZ0cV", forHTTPHeaderField: "X-API-Key")
    request.setValue(title, forHTTPHeaderField: "X-Song-Title")
    request.setValue(artist, forHTTPHeaderField: "X-Song-Artist")
    
    let (data, response) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(AnalysisResult.self, from: data)
}
```

### Configure in MacStudioServerManager.swift
```swift
class MacStudioServerManager: ObservableObject {
    private let apiKey = "xK7mP9nR4tL2wQ8vH5jN3bF6gY1aZ0cV" // Store securely!
    
    func analyzeAudio(audioData: Data, title: String, artist: String) async throws {
        // ...existing code...
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        // ...
    }
}
```

---

## 🌐 Deployment Options

### Option 1: Home Network (Your Mac Studio)
**Best for:** Personal use + beta testing
- Keep server running on Mac Studio
- Give testers your home IP + port
- **Requires:** Router port forwarding (5050 → your Mac)
- **Security:** API keys protect access

**Setup:**
1. Get your Mac's local IP: `ifconfig | grep "inet "`
2. Forward port 5050 in router settings
3. Find your public IP: `curl ifconfig.me`
4. Share: `http://YOUR_PUBLIC_IP:5050`

### Option 2: Cloud Server (Recommended for Production)
**Best for:** Commercial deployment
- Deploy to AWS, Google Cloud, or DigitalOcean
- Get SSL certificate (Let's Encrypt)
- Use domain name: `https://api.yourapp.com`

**Benefits:**
- ✅ Always online (99.9% uptime)
- ✅ HTTPS encryption
- ✅ Scalable (add more servers)
- ✅ Professional

### Option 3: Hybrid (Recommended)
**Best for:** You right now
- Development: localhost (no auth)
- Beta testing: Home server (API keys)
- Production: Cloud server (API keys + SSL)

---

## 🔐 Security Best Practices

### API Key Storage
**❌ DON'T:**
- Commit keys to git
- Share keys in screenshots
- Hardcode in public code

**✅ DO:**
- Store in Keychain (iOS)
- Use environment variables
- One key per device/user
- Rotate keys periodically

### iOS App Security
```swift
// Store API key in Keychain
class KeychainManager {
    static func getAPIKey() -> String? {
        // Retrieve from keychain
    }
    
    static func setAPIKey(_ key: String) {
        // Store in keychain
    }
}
```

### Monitor Usage
```bash
# Check who's using your API
python3 manage_api_keys.py list

# Investigate suspicious activity
python3 manage_api_keys.py show 3
```

---

## 📊 Pricing Tiers (Future)

### Free Tier
- 100 requests/day
- Personal use only
- Community support

### Pro Tier ($9.99/month)
- 10,000 requests/day
- Priority support
- Advanced analytics

### Enterprise Tier (Custom pricing)
- Unlimited requests
- SLA guarantees
- Dedicated support
- Custom features

---

## 🛠️ Maintenance

### View Server Logs
```bash
tail -f ~/Music/AudioAnalysisCache/server.log
```

### Database Backup
```bash
cp ~/Music/audio_analysis_cache.db ~/Music/audio_analysis_cache.db.backup
```

### Reset Everything (careful!)
```bash
# Clear cache and stats
curl -X POST http://localhost:5050/cache/clear

# Regenerate all API keys
rm ~/Music/audio_analysis_cache.db
python3 analyze_server.py  # Will recreate DB
```

---

## 🚨 Troubleshooting

### "API key required" error
- Check PRODUCTION_MODE is set
- Verify API key in request header
- Key format: `X-API-Key: your-key-here`

### "Rate limit exceeded"
- Wait 1 minute (60 req/min limit)
- Or increase limit per key
- Consider upgrading tier

### "Invalid API key"
- Check key is active: `python3 manage_api_keys.py show 1`
- Verify no typos in key
- Check daily limit not exceeded

### Can't connect remotely
- Verify port forwarding
- Check firewall settings
- Test with: `curl http://YOUR_IP:5050/health`

---

## 📈 Scaling Up

When you outgrow your Mac Studio:

1. **Add Load Balancer** - Multiple server instances
2. **Add Redis** - Better rate limiting
3. **Add PostgreSQL** - Better than SQLite
4. **Add CDN** - Cache analysis results globally
5. **Add Monitoring** - DataDog, New Relic

---

## 💡 Next Steps

1. ✅ Start in development mode (done!)
2. 🔑 Create API keys for your devices
3. 📱 Update your iOS app to use keys
4. 🧪 Test with beta testers
5. ☁️ Deploy to cloud when ready
6. 💰 Set up billing (Stripe integration)

---

## 🆘 Need Help?

Check the logs first:
```bash
tail -100 ~/Music/AudioAnalysisCache/server.log
```

Common issues and solutions are logged with emoji indicators:
- ✅ Success
- ❌ Error
- ⚠️ Warning
- 🔒 Security event
