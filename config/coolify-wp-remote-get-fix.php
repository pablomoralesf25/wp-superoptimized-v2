<?php
/**
 * COOLIFY-SPECIFIC wp_remote_get() FIXES
 * Addresses networking and SSL issues in Coolify's containerized environment
 */

// ========================================
// COOLIFY NETWORKING FIXES
// ========================================

// Fix DNS resolution in Docker containers
add_filter('http_request_args', function($args, $url) {
    // Add custom DNS servers for better resolution in containers
    if (!isset($args['timeout'])) {
        $args['timeout'] = 30;
    }
    
    // Increase timeout for containerized environments
    $args['timeout'] = max($args['timeout'], 30);
    
    // Add user agent to prevent blocking
    if (!isset($args['user-agent'])) {
        $args['user-agent'] = 'WordPress/' . get_bloginfo('version') . '; ' . get_bloginfo('url');
    }
    
    return $args;
}, 10, 2);

// ========================================
// SSL CERTIFICATE FIXES FOR COOLIFY
// ========================================

// Fix SSL verification issues in Docker containers
add_filter('https_ssl_verify', '__return_false'); // Temporary fix for development
add_filter('https_local_ssl_verify', '__return_false');

// Custom SSL context for wp_remote_get()
add_filter('http_request_args', function($args, $url) {
    // Only apply SSL fixes for HTTPS URLs
    if (strpos($url, 'https://') === 0) {
        // Set proper CA bundle path for Docker container
        $args['sslcertificates'] = '/etc/ssl/certs/ca-certificates.crt';
        
        // Add SSL context options
        if (!isset($args['stream_context'])) {
            $args['stream_context'] = array();
        }
        
        $args['stream_context']['ssl'] = array(
            'verify_peer' => true,
            'verify_peer_name' => true,
            'cafile' => '/etc/ssl/certs/ca-certificates.crt',
            'capath' => '/etc/ssl/certs/',
            'allow_self_signed' => false,
            'SNI_enabled' => true,
        );
    }
    
    return $args;
}, 5, 2);

// ========================================
// COOLIFY REVERSE PROXY FIXES
// ========================================

// Handle X-Forwarded headers from Coolify's reverse proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
    $_SERVER['SERVER_PORT'] = 443;
}

if (isset($_SERVER['HTTP_X_FORWARDED_HOST'])) {
    $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_X_FORWARDED_HOST'];
}

if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_X_FORWARDED_FOR'];
}

// ========================================
// DOCKER NETWORKING FIXES
// ========================================

// Fix for Docker internal networking
add_filter('pre_http_request', function($preempt, $parsed_args, $url) {
    // Skip if already handled
    if ($preempt !== false) {
        return $preempt;
    }
    
    // Add specific fixes for common WordPress API endpoints
    $wordpress_apis = [
        'api.wordpress.org',
        'downloads.wordpress.org',
        'wordpress.org'
    ];
    
    $parsed_url = parse_url($url);
    if (isset($parsed_url['host']) && in_array($parsed_url['host'], $wordpress_apis)) {
        // Ensure proper headers for WordPress API calls
        if (!isset($parsed_args['headers'])) {
            $parsed_args['headers'] = array();
        }
        
        $parsed_args['headers']['Accept'] = 'application/json, */*';
        $parsed_args['headers']['Accept-Encoding'] = 'gzip, deflate';
        
        // Use WordPress's built-in HTTP API with our custom args
        return wp_remote_request($url, $parsed_args);
    }
    
    return $preempt;
}, 10, 3);

// ========================================
// COOLIFY ENVIRONMENT DETECTION
// ========================================

// Detect if running in Coolify environment
function is_coolify_environment() {
    return (
        getenv('COOLIFY_APP_ID') !== false ||
        getenv('COOLIFY_PROJECT_ID') !== false ||
        isset($_SERVER['COOLIFY_APP_ID']) ||
        isset($_SERVER['COOLIFY_PROJECT_ID'])
    );
}

// Apply Coolify-specific fixes only in Coolify environment
if (is_coolify_environment()) {
    
    // ========================================
    // COOLIFY-SPECIFIC HTTP CLIENT FIXES
    // ========================================
    
    // Override default HTTP transport for better compatibility
    add_filter('http_api_transports', function($transports, $args, $url) {
        // Prioritize cURL over streams in containerized environment
        if (in_array('curl', $transports)) {
            $transports = array_diff($transports, ['curl']);
            array_unshift($transports, 'curl');
        }
        return $transports;
    }, 10, 3);
    
    // Custom cURL options for Coolify
    add_filter('http_request_args', function($args, $url) {
        if (!isset($args['curl_options'])) {
            $args['curl_options'] = array();
        }
        
        // Coolify-specific cURL options
        $args['curl_options'][CURLOPT_FOLLOWLOCATION] = true;
        $args['curl_options'][CURLOPT_MAXREDIRS] = 5;
        $args['curl_options'][CURLOPT_CONNECTTIMEOUT] = 30;
        $args['curl_options'][CURLOPT_TIMEOUT] = 60;
        $args['curl_options'][CURLOPT_USERAGENT] = 'WordPress/' . get_bloginfo('version') . '; Coolify';
        
        // SSL options for Docker environment
        $args['curl_options'][CURLOPT_SSL_VERIFYPEER] = true;
        $args['curl_options'][CURLOPT_SSL_VERIFYHOST] = 2;
        $args['curl_options'][CURLOPT_CAINFO] = '/etc/ssl/certs/ca-certificates.crt';
        $args['curl_options'][CURLOPT_CAPATH] = '/etc/ssl/certs/';
        
        // DNS options for container networking
        $args['curl_options'][CURLOPT_DNS_USE_GLOBAL_CACHE] = false;
        $args['curl_options'][CURLOPT_DNS_CACHE_TIMEOUT] = 60;
        
        return $args;
    }, 1, 2);
    
    // ========================================
    // COOLIFY LOGGING FOR DEBUGGING
    // ========================================
    
    // Log wp_remote_get() attempts for debugging
    add_action('http_api_debug', function($response, $context, $transport, $args, $url) {
        if (defined('WP_DEBUG') && WP_DEBUG) {
            error_log(sprintf(
                'Coolify wp_remote_get(): %s | Transport: %s | Response Code: %s | URL: %s',
                $context,
                $transport,
                is_wp_error($response) ? 'ERROR: ' . $response->get_error_message() : wp_remote_retrieve_response_code($response),
                $url
            ));
        }
    }, 10, 5);
}

// ========================================
// EMERGENCY FALLBACK FOR CRITICAL APIS
// ========================================

// Fallback function for critical WordPress API calls
function coolify_wp_remote_get_fallback($url, $args = array()) {
    // Try multiple methods in order of preference
    $methods = ['curl', 'streams', 'fsockopen'];
    
    foreach ($methods as $method) {
        $args['_transport'] = $method;
        $response = wp_remote_get($url, $args);
        
        if (!is_wp_error($response) && wp_remote_retrieve_response_code($response) === 200) {
            return $response;
        }
    }
    
    // If all methods fail, try with SSL verification disabled (last resort)
    $args['sslverify'] = false;
    return wp_remote_get($url, $args);
}

// ========================================
// WORDPRESS CORE UPDATE FIX
// ========================================

// Fix WordPress core update checks in Coolify
add_filter('pre_http_request', function($preempt, $parsed_args, $url) {
    // Handle WordPress core update checks specifically
    if (strpos($url, 'api.wordpress.org/core/version-check') !== false) {
        // Use our fallback method for critical API calls
        return coolify_wp_remote_get_fallback($url, $parsed_args);
    }
    
    return $preempt;
}, 5, 3);

// ========================================
// PLUGIN/THEME UPDATE FIXES
// ========================================

// Fix plugin and theme update checks
add_filter('pre_http_request', function($preempt, $parsed_args, $url) {
    // Handle plugin/theme update checks
    if (strpos($url, 'api.wordpress.org/plugins/update-check') !== false ||
        strpos($url, 'api.wordpress.org/themes/update-check') !== false) {
        return coolify_wp_remote_get_fallback($url, $parsed_args);
    }
    
    return $preempt;
}, 5, 3);

// ========================================
// HEALTH CHECK ENDPOINT
// ========================================

// Add a health check endpoint to test wp_remote_get()
add_action('wp_ajax_nopriv_coolify_test_remote_get', 'coolify_test_remote_get');
add_action('wp_ajax_coolify_test_remote_get', 'coolify_test_remote_get');

function coolify_test_remote_get() {
    $test_url = 'https://api.wordpress.org/core/version-check/1.7/';
    $response = wp_remote_get($test_url);
    
    if (is_wp_error($response)) {
        wp_die(json_encode([
            'status' => 'error',
            'message' => $response->get_error_message(),
            'environment' => 'Coolify: ' . (is_coolify_environment() ? 'Yes' : 'No')
        ]));
    } else {
        wp_die(json_encode([
            'status' => 'success',
            'response_code' => wp_remote_retrieve_response_code($response),
            'environment' => 'Coolify: ' . (is_coolify_environment() ? 'Yes' : 'No'),
            'body_length' => strlen(wp_remote_retrieve_body($response))
        ]));
    }
}

?>
