<?php
/**
 * MAXIMUM PERFORMANCE WORDPRESS CONFIGURATION
 * Add these optimizations to wp-config.php for extreme speed
 */

// ========================================
// PERFORMANCE OPTIMIZATIONS
// ========================================

// Memory limits for maximum performance
define('WP_MEMORY_LIMIT', '512M');
define('WP_MAX_MEMORY_LIMIT', '1024M');

// Increase maximum execution time
ini_set('max_execution_time', 300);
ini_set('max_input_time', 300);

// ========================================
// CACHING OPTIMIZATIONS
// ========================================

// Enable object caching with Redis
define('WP_CACHE', true);
define('WP_CACHE_KEY_SALT', 'your-site-name');

// Redis configuration for object caching
define('WP_REDIS_HOST', 'localhost');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DATABASE', 0);

// Enable Redis persistent connections
define('WP_REDIS_PERSISTENT', true);

// ========================================
// DATABASE OPTIMIZATIONS
// ========================================

// Increase database timeout
define('DB_TIMEOUT', 30);

// Enable MySQL query caching
define('MYSQL_CLIENT_FLAGS', MYSQL_CLIENT_COMPRESS);

// Optimize database queries
define('WP_ALLOW_REPAIR', false); // Only enable when needed

// ========================================
// FILE SYSTEM OPTIMIZATIONS
// ========================================

// Use direct file system method (fastest)
define('FS_METHOD', 'direct');

// Optimize file permissions
define('FS_CHMOD_DIR', (0755 & ~ umask()));
define('FS_CHMOD_FILE', (0644 & ~ umask()));

// ========================================
// WORDPRESS CORE OPTIMIZATIONS
// ========================================

// Disable file editing from admin
define('DISALLOW_FILE_EDIT', true);

// Disable plugin/theme installation
define('DISALLOW_FILE_MODS', false); // Set to true in production

// Increase autosave interval (reduce server load)
define('AUTOSAVE_INTERVAL', 300); // 5 minutes

// Limit post revisions
define('WP_POST_REVISIONS', 5);

// Empty trash automatically
define('EMPTY_TRASH_DAYS', 7);

// ========================================
// MEDIA OPTIMIZATIONS
// ========================================

// Increase image quality
define('JPEG_QUALITY', 90);

// Enable image compression
define('WP_IMAGE_EDITOR', 'WP_Image_Editor_Imagick');

// ========================================
// SECURITY OPTIMIZATIONS (Performance Impact)
// ========================================

// Disable XML-RPC (if not needed)
// define('XMLRPC_DISABLED', true);

// Force SSL (if using HTTPS)
// define('FORCE_SSL_ADMIN', true);

// Security keys (generate new ones)
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

// ========================================
// DEBUGGING (Disable in production)
// ========================================

// Disable debugging for maximum performance
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);
define('SCRIPT_DEBUG', false);

// ========================================
// HEARTBEAT OPTIMIZATION
// ========================================

// Reduce heartbeat frequency to save resources
define('WP_HEARTBEAT_INTERVAL', 60); // 60 seconds instead of 15

// ========================================
// CRON OPTIMIZATIONS
// ========================================

// Disable WP Cron (use system cron instead for better performance)
define('DISABLE_WP_CRON', true);

// ========================================
// MULTISITE OPTIMIZATIONS (if using multisite)
// ========================================

// Enable multisite (uncomment if needed)
// define('WP_ALLOW_MULTISITE', true);
// define('MULTISITE', true);
// define('SUBDOMAIN_INSTALL', false);
// define('DOMAIN_CURRENT_SITE', 'your-domain.com');
// define('PATH_CURRENT_SITE', '/');
// define('SITE_ID_CURRENT_SITE', 1);
// define('BLOG_ID_CURRENT_SITE', 1);

// ========================================
// LITESPEED CACHE OPTIMIZATIONS
// ========================================

// LiteSpeed Cache specific optimizations
define('LSCACHE_ADV_CACHE', true);
define('LSCACHE_OBJECT_CACHE', true);

// ========================================
// CUSTOM OPTIMIZATIONS
// ========================================

// Increase memory for image processing
ini_set('memory_limit', '512M');

// Optimize session handling
ini_set('session.gc_maxlifetime', 3600);
ini_set('session.gc_probability', 1);
ini_set('session.gc_divisor', 100);

// ========================================
// SSL/TLS OPTIMIZATIONS FOR wp_remote_get()
// ========================================

// Fix wp_remote_get() SSL issues
define('CURLOPT_SSL_VERIFYPEER', false);
define('CURLOPT_SSL_VERIFYHOST', false);

// Set proper CA bundle path
define('CURL_CA_BUNDLE', '/etc/ssl/certs/ca-certificates.crt');

// HTTP timeout settings
define('WP_HTTP_TIMEOUT', 30);
define('WP_HTTP_BLOCK_EXTERNAL', false);

// ========================================
// ADDITIONAL PERFORMANCE TWEAKS
// ========================================

// Disable pingbacks and trackbacks
define('WP_DISABLE_PINGBACKS', true);

// Limit login attempts (if using security plugin)
define('WP_LOGIN_ATTEMPTS', 5);

// Optimize database queries
define('WP_USE_EXT_MYSQL', false);

// Enable Gzip compression
if (!defined('WP_GZIP_COMPRESSION')) {
    define('WP_GZIP_COMPRESSION', true);
}

// ========================================
// ENVIRONMENT SPECIFIC SETTINGS
// ========================================

// Set environment type
define('WP_ENVIRONMENT_TYPE', 'production'); // or 'development', 'staging'

// Optimize for production
if (WP_ENVIRONMENT_TYPE === 'production') {
    // Disable all debugging
    define('WP_DEBUG', false);
    define('WP_DEBUG_LOG', false);
    define('WP_DEBUG_DISPLAY', false);
    
    // Enable all caching
    define('WP_CACHE', true);
    
    // Disable file modifications
    define('DISALLOW_FILE_MODS', true);
    define('DISALLOW_FILE_EDIT', true);
    
    // Force SSL
    define('FORCE_SSL_ADMIN', true);
}

// ========================================
// CUSTOM FUNCTIONS FOR PERFORMANCE
// ========================================

// Remove query strings from static resources
function remove_query_strings() {
    if(!is_admin()) {
        add_filter('script_loader_src', 'remove_query_strings_split', 15);
        add_filter('style_loader_src', 'remove_query_strings_split', 15);
    }
}

function remove_query_strings_split($src){
    $output = preg_split("/(&ver|\?ver)/", $src);
    return $output[0];
}
add_action('init', 'remove_query_strings');

// Disable emojis for performance
function disable_emojis() {
    remove_action('wp_head', 'print_emoji_detection_script', 7);
    remove_action('admin_print_scripts', 'print_emoji_detection_script');
    remove_action('wp_print_styles', 'print_emoji_styles');
    remove_action('admin_print_styles', 'print_emoji_styles');
    remove_filter('the_content_feed', 'wp_staticize_emoji');
    remove_filter('comment_text_rss', 'wp_staticize_emoji');
    remove_filter('wp_mail', 'wp_staticize_emoji_for_email');
}
add_action('init', 'disable_emojis');

// Disable embeds for performance
function disable_embeds(){
    wp_dequeue_script('wp-embed');
}
add_action('wp_footer', 'disable_embeds');

// Remove WordPress version for security and performance
function remove_version() {
    return '';
}
add_filter('the_generator', 'remove_version');

?>
