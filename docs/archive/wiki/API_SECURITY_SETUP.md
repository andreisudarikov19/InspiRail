# API Security Setup Guide

## ⚠️ IMPORTANT: Securing Your NS API Key

This app uses the Nederlandse Spoorwegen (NS) API which requires an API key. **Never commit your API key to version control.**

### Initial Setup

1. **Create your `Secrets.xcconfig` file:**
   ```bash
   # Copy the template
   cp Secrets.xcconfig.template Secrets.xcconfig
   ```

2. **Add your API key:**
   - Open `Secrets.xcconfig`
   - Replace `YOUR_API_KEY_HERE` with your actual NS API key
   - Get your key from: https://apiportal.ns.nl

3. **Verify `.gitignore`:**
   Ensure this line exists in your `.gitignore`:
   ```
   Secrets.xcconfig
   ```

### Security Architecture

The app uses a **three-layer security approach**:

1. **Build Time**: API key is read from `Secrets.xcconfig` (not committed to Git)
2. **First Launch**: Key is automatically migrated to iOS Keychain
3. **Runtime**: All API requests use the key from Keychain (most secure)

### How It Works

```
Secrets.xcconfig (local only)
    ↓ (Build time)
Info.plist (embedded in app)
    ↓ (First launch)
iOS Keychain (encrypted storage)
    ↓ (Runtime)
API Requests
```

### For CI/CD Builds

When building on a CI/CD server:

1. **GitHub Actions / GitLab CI:**
   ```yaml
   - name: Create Secrets Config
     run: echo "API_KEY=${{ secrets.NS_API_KEY }}" > Secrets.xcconfig
   ```

2. **Xcode Cloud:**
   - Add `NS_API_KEY` as an environment variable in Xcode Cloud settings
   - Use a custom build script to generate `Secrets.xcconfig`

3. **Fastlane:**
   ```ruby
   lane :beta do
     create_secrets_file(api_key: ENV["NS_API_KEY"])
     build_app
   end
   ```

### Verifying Security

Run these checks before committing:

```bash
# 1. Ensure Secrets.xcconfig is NOT tracked
git status | grep -q "Secrets.xcconfig" && echo "⚠️ WARNING: Secrets file is tracked!" || echo "✅ Good"

# 2. Search for hardcoded keys (should return nothing)
git grep -n "<redacted>" && echo "⚠️ WARNING: API key found!" || echo "✅ Good"

# 3. Check .gitignore
grep -q "Secrets.xcconfig" .gitignore && echo "✅ Good" || echo "⚠️ WARNING: Add to .gitignore!"
```

### Emergency: If You Committed Your Key

If you accidentally committed your API key:

1. **Immediately revoke the key** at https://apiportal.ns.nl
2. **Generate a new key**
3. **Remove the key from Git history:**
   ```bash
   # Using BFG Repo-Cleaner (recommended)
   bfg --replace-text passwords.txt
   
   # Or using git-filter-branch
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch Secrets.xcconfig" \
     --prune-empty --tag-name-filter cat -- --all
   
   # Force push
   git push origin --force --all
   ```

### Alternative: Manual Keychain Entry

For extra security, you can skip build-time embedding:

1. Don't use `Secrets.xcconfig` at all
2. On first app launch, show a setup screen
3. User manually enters API key
4. App saves directly to Keychain

Implement by checking `KeychainManager.shared.hasAPIKey()` in your app delegate.

### Best Practices

✅ **DO:**
- Keep `Secrets.xcconfig` in `.gitignore`
- Use environment variables in CI/CD
- Rotate API keys periodically
- Use different keys for development and production

❌ **DON'T:**
- Commit API keys to Git
- Hardcode keys in source code
- Share keys in screenshots or documentation
- Use production keys in debug builds

### Testing Security

The app includes debug logging to verify security:

```swift
#if DEBUG
// On app launch, you'll see:
// "✅ API key saved to Keychain"
// "🔐 Using API key from Keychain"
#endif
```

### Additional Resources

- [NS API Portal](https://apiportal.ns.nl)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
- [OWASP Mobile Security](https://owasp.org/www-project-mobile-security/)
