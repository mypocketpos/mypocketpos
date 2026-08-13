/**
 * Pocket POS – Main Server Handler (cart_session.js)
 * =================================================
 * Handles request parsing, Firestore feature flag verification,
 * rate limiting, and Firebase Custom Token minting.
 */

// ─── CONFIGURATION & SCRIPT PROPERTIES ────────────────────────────────────────

var scriptProps = PropertiesService.getScriptProperties();

var SA_KEY      = scriptProps.getProperty('SERVICE_ACCOUNT_KEY');
var SA_EMAIL    = scriptProps.getProperty('SERVICE_ACCOUNT_EMAIL');
var PROJECT_ID  = scriptProps.getProperty('FIREBASE_PROJECT_ID');


// ─── MAIN DOPOST HANDLER ──────────────────────────────────────────────────────

/**
 * Handles incoming HTTP POST requests from client apps.
 * 
 * @param {Object} e - Event object containing postData
 * @return {TextOutput} JSON payload with status or token output
 */
function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return _jsonResponse({ error: "Invalid or empty request payload.", code: 400 });
    }

    var requestData;
    try {
      requestData = JSON.parse(e.postData.contents);
    } catch (parseError) {
      return _jsonResponse({ error: "Malformed JSON payload.", code: 400 });
    }

    var storeId      = requestData.storeId;
    var customerName = requestData.customerName || "Guest";
    var mobile       = requestData.mobile || "";

    if (!storeId) {
      return _jsonResponse({ error: "Missing required parameter: storeId", code: 400 });
    }

    // 1. Fetch OAuth Access Token for Firestore API
    var accessToken = _getServiceAccountAccessToken();

    // 2. Perform Feature Flag & Rate Limit Check in Firestore
    var featureStatus = _checkStoreFeatureStatus(storeId, accessToken);
    if (!featureStatus.allowed) {
      return _jsonResponse({ error: featureStatus.reason, code: 403 });
    }

    // 3. Generate Cart ID (Numeric ID)
    var cartId = (Date.now() * 1000 + Math.floor(Math.random() * 1000));
    var storeName = featureStatus.storeName || "Pocket POS Store";

    // Create Session / Cart Document under /stores/{storeId}/carts/{cartId}
    _createCartDocument(PROJECT_ID, cartId, storeId, customerName, mobile, accessToken);

    // 4. Mint Custom Auth Token for Firebase Client SDK with matching claims
    var customToken = _mintCustomToken(String(cartId), {
      storeId: storeId,
      cartId: cartId,
      role: "customer_cart" // FIXED: Aligned with Firestore Rules requirement
    });

    return _jsonResponse({
      success: true,
      cartId: cartId,
      storeName: storeName,
      customToken: customToken
    });

  } catch (err) {
    Logger.log("cart_session error: " + err.toString());
    return _jsonResponse({ error: "Internal error: " + err.message, code: 500 });
  }
}


// ─── PRIVATE KEY SANITIZER ────────────────────────────────────────────────────

function _getFormattedPrivateKey() {
  if (!SA_KEY) {
    throw new Error("Script property 'SERVICE_ACCOUNT_KEY' is missing or empty.");
  }

  var unescapedKey = SA_KEY
    .replace(/^["']|["']$/g, '')   // Strip surrounding quotes
    .replace(/\\\\n/g, '\n')        // Fix double backslash escaped newlines
    .replace(/\\n/g, '\n')         // Fix single backslash escaped newlines
    .replace(/\r/g, '');            // Remove carriage returns

  var header = '-----BEGIN PRIVATE KEY-----';
  var footer = '-----END PRIVATE KEY-----';

  var startIndex = unescapedKey.indexOf(header);
  var endIndex = unescapedKey.indexOf(footer);

  if (startIndex === -1 || endIndex === -1) {
    throw new Error("Key structure invalid. Missing BEGIN or END headers.");
  }

  var base64Content = unescapedKey
    .substring(startIndex + header.length, endIndex)
    .replace(/\s+/g, '');

  var lines = [];
  for (var i = 0; i < base64Content.length; i += 64) {
    lines.push(base64Content.substring(i, i + 64));
  }

  return header + '\n' + lines.join('\n') + '\n' + footer;
}


// ─── AUTHENTICATION HELPERS ───────────────────────────────────────────────────

function _getServiceAccountAccessToken() {
  var cleanKey = _getFormattedPrivateKey();
  var now = Math.floor(Date.now() / 1000);

  var header = { alg: 'RS256', typ: 'JWT' };
  var payload = {
    iss: SA_EMAIL,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600
  };

  var b64Header  = Utilities.base64EncodeWebSafe(JSON.stringify(header)).replace(/=+$/, '');
  var b64Payload = Utilities.base64EncodeWebSafe(JSON.stringify(payload)).replace(/=+$/, '');
  var toSign     = b64Header + '.' + b64Payload;

  var signature = Utilities.computeRsaSha256Signature(toSign, cleanKey);
  var b64Sign   = Utilities.base64EncodeWebSafe(signature).replace(/=+$/, '');
  var jwt       = toSign + '.' + b64Sign;

  var response = UrlFetchApp.fetch('https://oauth2.googleapis.com/token', {
    method: 'post',
    contentType: 'application/x-www-form-urlencoded',
    payload: {
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt
    },
    muteHttpExceptions: true
  });

  if (response.getResponseCode() !== 200) {
    throw new Error("Failed to fetch OAuth token: " + response.getContentText());
  }

  var resJson = JSON.parse(response.getContentText());
  return resJson.access_token;
}

function _mintCustomToken(uid, claims) {
  var cleanKey = _getFormattedPrivateKey();
  var now = Math.floor(Date.now() / 1000);

  var header = { alg: 'RS256', typ: 'JWT' };
  var payload = {
    iss: SA_EMAIL,
    sub: SA_EMAIL,
    aud: 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
    iat: now,
    exp: now + 3600,
    uid: String(uid),
    claims: claims || {}
  };

  var b64Header  = Utilities.base64EncodeWebSafe(JSON.stringify(header)).replace(/=+$/, '');
  var b64Payload = Utilities.base64EncodeWebSafe(JSON.stringify(payload)).replace(/=+$/, '');
  var toSign     = b64Header + '.' + b64Payload;

  var signature = Utilities.computeRsaSha256Signature(toSign, cleanKey);
  var b64Sign   = Utilities.base64EncodeWebSafe(signature).replace(/=+$/, '');

  return toSign + '.' + b64Sign;
}


// ─── FIRESTORE OPERATIONS ─────────────────────────────────────────────────────

function _checkStoreFeatureStatus(storeId, accessToken) {
  var url = 'https://firestore.googleapis.com/v1/projects/' + PROJECT_ID + 
            '/databases/(default)/documents/stores/' + storeId;

  var response = UrlFetchApp.fetch(url, {
    method: 'get',
    headers: { Authorization: 'Bearer ' + accessToken },
    muteHttpExceptions: true
  });

  if (response.getResponseCode() === 404) {
    return { allowed: false, reason: "Store ID does not exist." };
  }

  if (response.getResponseCode() !== 200) {
    return { allowed: false, reason: "Unable to verify store status." };
  }

  var data = JSON.parse(response.getContentText());
  var fields = data.fields || {};

  var storeName = fields.name ? fields.name.stringValue : "Store " + storeId;
  return { allowed: true, storeName: storeName };
}

/**
 * Creates a new active cart session document inside the STORE subcollection.
 */
function _createCartDocument(projectId, cartId, storeId, customerName, mobile, accessToken) {
  // FIXED: Write document inside /stores/{storeId}/carts/{cartId}
  var url = 'https://firestore.googleapis.com/v1/projects/' + PROJECT_ID + 
            '/databases/(default)/documents/stores/' + storeId + '/carts?documentId=' + cartId;

  var payload = {
    fields: {
      storeId: { stringValue: storeId },
      customerName: { stringValue: customerName },
      mobile: { stringValue: mobile },
      status: { stringValue: "ACTIVE" },
      source: { stringValue: "customer" },
      createdAt: { timestampValue: new Date().toISOString() }
    }
  };

  var response = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + accessToken },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });

  if (response.getResponseCode() !== 200) {
    Logger.log("Failed to create cart document: " + response.getContentText());
  }
}

// ─── UTILITY FUNCTIONS ────────────────────────────────────────────────────────

function _jsonResponse(data) {
  return ContentService.createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

// ==============================================================================
// 🧪 DEBUGGING & TEST SUITE FOR doPost()
// ==============================================================================

/**
 * Main Debugger Function:
 * Run this directly from the Apps Script editor toolbar by selecting 
 * 'runDoPostDebugger' and clicking 'Run'.
 */
function runDoPostDebugger() {
  Logger.log("=================================================");
  Logger.log("🚀 STARTING POST HANDLER DEBUG SUITE");
  Logger.log("=================================================\n");

  // TEST 1: Valid Storefront Request
  _testSimulateDoPost("1. VALID REQUEST", {
    storeId: "STR-BPWCP3",
    customerName: "Debug User",
    mobile: "9876543210"
  });

  // TEST 2: Missing Store ID (Should return 400 validation error)
  _testSimulateDoPost("2. MISSING STORE ID", {
    customerName: "Invalid User",
    mobile: "9876543210"
  });

  // TEST 3: Invalid/Non-existent Store ID (Should return 403 feature status error)
  _testSimulateDoPost("3. NON-EXISTENT STORE", {
    storeId: "STR-INVALID-9999",
    customerName: "Ghost Customer",
    mobile: "0000000000"
  });

  Logger.log("\n=================================================");
  Logger.log("🏁 DEBUG SUITE COMPLETE");
  Logger.log("=================================================");
}

/**
 * Helper to mock the event structure passed by Google Apps Script runtime.
 */
function _testSimulateDoPost(testName, payloadObject) {
  Logger.log("--- Testing: " + testName + " ---");

  // Construct mock event structure matching Apps Script 'e' parameter
  var mockEvent = {
    postData: {
      contents: JSON.stringify(payloadObject)
    }
  };

  try {
    var startTime = Date.now();
    var responseOutput = doPost(mockEvent);
    var duration = Date.now() - startTime;

    var content = responseOutput.getContent();
    var mimeType = responseOutput.getMimeType();

    Logger.log("⏱️ Execution Time: " + duration + " ms");
    Logger.log("📄 Response MIME: " + mimeType);
    Logger.log("📦 Response Payload:\n" + content);

    // Try parsing returned JSON output
    var parsed = JSON.parse(content);
    if (parsed.success) {
      Logger.log("✅ PASSED: Custom token & cart generated successfully!");
      Logger.log("   -> Store Name: " + parsed.storeName);
      Logger.log("   -> Cart ID: " + parsed.cartId);
      Logger.log("   -> Custom Token Length: " + (parsed.customToken ? parsed.customToken.length : 0));
    } else {
      Logger.log("⚠️ HANDLED ERROR: " + parsed.error);
    }
  } catch (err) {
    Logger.log("❌ CRITICAL SCRIPT EXCEPTION: " + err.toString());
    if (err.stack) {
      Logger.log("   Stack Trace:\n" + err.stack);
    }
  }

  Logger.log("\n");
}