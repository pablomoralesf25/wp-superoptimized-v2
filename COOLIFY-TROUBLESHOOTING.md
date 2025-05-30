# 🔧 COOLIFY wp_remote_get() TROUBLESHOOTING GUIDE

This guide specifically addresses **wp_remote_get()** issues in **Coolify's containerized environment** and provides maximum speed optimizations.

## 🎯 Coolify-Specific Issues

### **Why wp_remote_get() Fails in Coolify**

1. **Container Networking**: Docker containers have isolated networking
2. **Reverse Proxy**: Coolify's reverse proxy can interfere with outbound requests
3. **SSL Certificate Issues**: Container CA certificates may be outdated
4. **DNS Resolution**: Container DNS may not resolve external domains properly
5. **Firewall Rules**: Container networking rules may block outbound HTTPS

## 🔧 **IMPLEMENTED FIXES**

### **1. Coolify-Specific PHP Configuration**

<augment_code_snippet path="config/coolify-wp-remote-get-fix.php" mode="EXCERPT">
````php
// Coolify environment detection
function is_coolify_environment() {
    return (
        getenv('COOLIFY_APP_ID') !== false ||
        getenv('COOLIFY_PROJECT_ID') !== false ||
        isset($_SERVER['COOLIFY_APP_ID']) ||
        isset($_SERVER['COOLIFY_PROJECT_ID'])
    );
}
````
</augment_code_snippet>

### **2. Enhanced SSL Certificate Handling**

<augment_code_snippet path="config/php.ini.template" mode="EXCERPT">
````ini
; CURL AND SSL CONFIGURATION FOR wp_remote_get()
curl.cainfo = "/etc/ssl/certs/ca-certificates.crt"
openssl.cafile = "/etc/ssl/certs/ca-certificates.crt"
openssl.capath = "/etc/ssl/certs/"
````
</augment_code_snippet>

### **3. Container Networking Optimizations**

<augment_code_snippet path="Dockerfile" mode="EXCERPT">
````dockerfile
# COOLIFY-SPECIFIC NETWORKING FIXES
RUN apt-get update && apt-get install -y \
    dnsutils \
    iputils-ping \
    telnet \
    netcat-openbsd
````
</augment_code_snippet>

### **4. DNS Resolution Fixes**

<augment_code_snippet path="Dockerfile" mode="EXCERPT">
````dockerfile
# Configure DNS for better resolution in Docker containers
RUN echo "nameserver 8.8.8.8" >> /etc/resolv.conf && \
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf && \
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
````
</augment_code_snippet>

## 🧪 **TESTING wp_remote_get()**

### **1. Built-in Health Check**
Access the health check endpoint:
```
https://your-domain.com/wp-admin/admin-ajax.php?action=coolify_test_remote_get
```

### **2. WP-CLI Testing**
```bash
# Test basic wp_remote_get()
wp eval "wp_remote_get('https://api.wordpress.org/core/version-check/1.7/');" --allow-root

# Test with verbose output
wp eval "
\$response = wp_remote_get('https://api.wordpress.org/core/version-check/1.7/');
if (is_wp_error(\$response)) {
    echo 'ERROR: ' . \$response->get_error_message();
} else {
    echo 'SUCCESS: Response code ' . wp_remote_retrieve_response_code(\$response);
}
" --allow-root
```

### **3. Manual cURL Testing**
```bash
# Test SSL connectivity
curl -I https://api.wordpress.org/core/version-check/1.7/

# Test with verbose SSL info
curl -v https://api.wordpress.org/core/version-check/1.7/

# Test DNS resolution
nslookup api.wordpress.org
```

## 🔍 **TROUBLESHOOTING STEPS**

### **Step 1: Check Container Networking**
```bash
# Test external connectivity
ping -c 3 8.8.8.8

# Test DNS resolution
nslookup api.wordpress.org

# Test HTTPS connectivity
curl -I https://api.wordpress.org/core/version-check/1.7/
```

### **Step 2: Verify SSL Certificates**
```bash
# Update CA certificates
update-ca-certificates --fresh

# Check certificate bundle
ls -la /etc/ssl/certs/ca-certificates.crt

# Test SSL handshake
openssl s_client -connect api.wordpress.org:443 -servername api.wordpress.org
```

### **Step 3: Check PHP Configuration**
```bash
# Verify cURL is enabled
php -m | grep curl

# Check SSL settings
php -i | grep -E "(curl|ssl|openssl)"

# Test PHP cURL directly
php -r "
\$ch = curl_init('https://api.wordpress.org/core/version-check/1.7/');
curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt(\$ch, CURLOPT_SSL_VERIFYPEER, true);
curl_setopt(\$ch, CURLOPT_CAINFO, '/etc/ssl/certs/ca-certificates.crt');
\$result = curl_exec(\$ch);
if (curl_error(\$ch)) {
    echo 'cURL Error: ' . curl_error(\$ch);
} else {
    echo 'Success: ' . curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
}
curl_close(\$ch);
"
```

### **Step 4: WordPress-Specific Checks**
```bash
# Check WordPress constants
wp config get WP_HTTP_TIMEOUT --allow-root
wp config get WP_HTTP_BLOCK_EXTERNAL --allow-root

# Test WordPress HTTP API
wp eval "
\$response = wp_remote_get('https://httpbin.org/get');
if (is_wp_error(\$response)) {
    echo 'Error: ' . \$response->get_error_message();
} else {
    echo 'Success: ' . wp_remote_retrieve_response_code(\$response);
}
" --allow-root
```

## 🚨 **COMMON ERROR MESSAGES & SOLUTIONS**

### **Error: "cURL error 60: SSL certificate problem"**
```bash
# Solution 1: Update CA certificates
update-ca-certificates --fresh

# Solution 2: Check PHP SSL configuration
php -i | grep curl.cainfo

# Solution 3: Verify certificate bundle exists
ls -la /etc/ssl/certs/ca-certificates.crt
```

### **Error: "cURL error 7: Failed to connect"**
```bash
# Solution 1: Test DNS resolution
nslookup api.wordpress.org

# Solution 2: Check firewall rules
iptables -L OUTPUT

# Solution 3: Test direct connectivity
telnet api.wordpress.org 443
```

### **Error: "cURL error 28: Operation timed out"**
```bash
# Solution 1: Increase timeout
wp config set WP_HTTP_TIMEOUT 60 --raw --allow-root

# Solution 2: Check network latency
ping -c 5 api.wordpress.org

# Solution 3: Test with different DNS
echo "nameserver 1.1.1.1" > /etc/resolv.conf
```

## 🔧 **COOLIFY-SPECIFIC ENVIRONMENT VARIABLES**

Add these to your Coolify environment variables:

```env
# WordPress HTTP settings
WP_HTTP_TIMEOUT=60
WP_HTTP_BLOCK_EXTERNAL=false

# SSL/TLS settings
CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
SSL_VERIFY_PEER=true

# Coolify detection
COOLIFY_APP_ID=your-app-id
COOLIFY_PROJECT_ID=your-project-id
```

## 📊 **PERFORMANCE MONITORING**

### **Run Performance Monitor**
```bash
# Check overall system health
bash /usr/local/bin/performance-monitor.sh

# Check wp_remote_get() specifically
wp eval "
\$start = microtime(true);
\$response = wp_remote_get('https://api.wordpress.org/core/version-check/1.7/');
\$time = microtime(true) - \$start;
echo 'Time: ' . round(\$time * 1000, 2) . 'ms' . PHP_EOL;
if (is_wp_error(\$response)) {
    echo 'Error: ' . \$response->get_error_message();
} else {
    echo 'Success: ' . wp_remote_retrieve_response_code(\$response);
}
" --allow-root
```

## 🎯 **COOLIFY DEPLOYMENT CHECKLIST**

### **Before Deployment:**
- [ ] Verify Coolify environment variables are set
- [ ] Check reverse proxy configuration
- [ ] Ensure proper networking setup

### **After Deployment:**
- [ ] Test DNS resolution: `nslookup api.wordpress.org`
- [ ] Test SSL connectivity: `curl -I https://api.wordpress.org/core/version-check/1.7/`
- [ ] Test wp_remote_get(): Access health check endpoint
- [ ] Run performance monitor: `bash /usr/local/bin/performance-monitor.sh`
- [ ] Check WordPress updates work properly

### **Ongoing Monitoring:**
- [ ] Monitor wp_remote_get() success rate
- [ ] Check SSL certificate expiry
- [ ] Monitor network connectivity
- [ ] Review error logs regularly

## 🆘 **EMERGENCY FIXES**

### **Quick SSL Fix (Development Only)**
```php
// Add to wp-config.php (DEVELOPMENT ONLY)
add_filter('https_ssl_verify', '__return_false');
add_filter('https_local_ssl_verify', '__return_false');
```

### **Force HTTP Instead of HTTPS (Last Resort)**
```php
// Add to wp-config.php (NOT RECOMMENDED)
add_filter('pre_http_request', function($preempt, $parsed_args, $url) {
    if (strpos($url, 'https://api.wordpress.org') === 0) {
        $url = str_replace('https://', 'http://', $url);
        return wp_remote_request($url, $parsed_args);
    }
    return $preempt;
}, 10, 3);
```

## 📞 **SUPPORT & DEBUGGING**

### **Enable Debug Logging**
```php
// Add to wp-config.php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);

// Check logs
tail -f /var/www/vhosts/localhost/html/wp-content/debug.log
```

### **Coolify-Specific Logs**
```bash
# Check container logs
docker logs your-container-name

# Check Coolify proxy logs
docker logs coolify-proxy

# Check system logs
journalctl -u docker
```

---

**🚀 This guide provides comprehensive solutions for wp_remote_get() issues in Coolify environments while maintaining maximum performance optimizations.**
