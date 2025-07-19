# Browser Extension Approach (No Webhooks Needed)

Create a simple browser extension that syncs PR data as you browse GitHub.

## How It Works
- Extension runs when you visit vets-api PR pages
- Extracts PR and check data from the page
- Sends to your dashboard API
- No rate limits (uses your browser session)

## Quick Setup

### 1. Create Extension Files

Create folder `pr-dashboard-extension/`:

**manifest.json**:
```json
{
  "manifest_version": 3,
  "name": "PR Dashboard Sync",
  "version": "1.0",
  "description": "Syncs PR data to dashboard",
  "permissions": ["activeTab"],
  "host_permissions": [
    "https://github.com/*",
    "https://ai-dashboards.onrender.com/*"
  ],
  "content_scripts": [
    {
      "matches": ["https://github.com/department-of-veterans-affairs/vets-api/pull/*"],
      "js": ["content.js"]
    }
  ]
}
```

**content.js**:
```javascript
// Runs on PR pages
const API_URL = 'https://ai-dashboards.onrender.com';
const ADMIN_TOKEN = 'your_admin_token'; // Or use extension storage

function extractPRData() {
  const prNumber = window.location.pathname.match(/pull\/(\d+)/)[1];
  const title = document.querySelector('.js-issue-title').textContent.trim();
  const author = document.querySelector('.author').textContent;
  
  // Extract check status
  const checksElement = document.querySelector('.merge-status-list');
  const checkCounts = checksElement?.textContent.match(/(\d+)\s+of\s+(\d+)/);
  
  return {
    number: prNumber,
    title: title,
    author: author,
    url: window.location.href,
    checks_passed: checkCounts ? checkCounts[1] : 0,
    checks_total: checkCounts ? checkCounts[2] : 0,
    scraped_at: new Date().toISOString()
  };
}

// Send to API
async function syncPR() {
  const prData = extractPRData();
  
  try {
    await fetch(`${API_URL}/api/v1/browser_sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${ADMIN_TOKEN}`
      },
      body: JSON.stringify(prData)
    });
    console.log('PR synced:', prData.number);
  } catch (error) {
    console.error('Sync failed:', error);
  }
}

// Run on page load
setTimeout(syncPR, 2000);
```

### 2. Install Extension
1. Open Chrome/Edge
2. Go to `chrome://extensions`
3. Enable "Developer mode"
4. Click "Load unpacked"
5. Select your `pr-dashboard-extension` folder

### 3. Use It
- Just browse PRs normally
- Extension auto-syncs data as you view PRs
- No rate limits!

## Benefits
- Uses your authenticated GitHub session
- No API rate limits
- Syncs as you work
- No server/cron needed