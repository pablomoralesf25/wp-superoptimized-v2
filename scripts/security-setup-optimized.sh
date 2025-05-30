#!/bin/bash

# Optimized WordPress Security Setup for Performance
# This script reduces aggressive anti-bot measures that cause slowdowns

# Configurazione logging più robusta
if [ ! -d "/var/log/wordpress" ]; then
    mkdir -p /var/log/wordpress
fi

LOGFILE="/var/log/wordpress/security-setup-optimized.log"
exec 1> >(tee -a "$LOGFILE") 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting OPTIMIZED security setup script..."

# Verifichiamo che WP-CLI sia disponibile
if ! command -v wp &> /dev/null; then
    echo "ERROR: wp-cli non è installato"
    exit 1
fi

# Verifichiamo che WordPress sia installato
if ! wp core is-installed --allow-root; then
    echo "ERROR: WordPress non è ancora installato"
    exit 1
fi

# Verifichiamo i permessi
if [ ! -w "/var/www/vhosts/localhost/html" ]; then
    echo "ERROR: Permessi insufficienti sulla directory di WordPress"
    exit 1
fi

# Disabilita tutti gli aggiornamenti automatici
echo "Disabling automatic updates..."
wp config set WP_AUTO_UPDATE_CORE false --raw --allow-root
wp config set AUTOMATIC_UPDATER_DISABLED true --raw --allow-root
wp config set WP_AUTO_UPDATE_PLUGINS false --raw --allow-root
wp config set WP_AUTO_UPDATE_THEMES false --raw --allow-root
wp config set DISALLOW_FILE_MODS true --raw --allow-root
wp config set DISALLOW_FILE_EDIT true --raw --allow-root
wp config set WP_CLI_DISABLE_AUTO_CHECK_UPDATE true --raw --allow-root

echo "Automatic updates disabled successfully"

# Rimuovi plugin non necessari
echo "Removing unnecessary plugins..."
wp plugin delete akismet --allow-root 2>/dev/null || true
wp plugin delete hello --allow-root 2>/dev/null || true

# Funzione per installare e configurare LiteSpeed Cache con settings OTTIMIZZATI
setup_litespeed_cache_optimized() {
    echo "Setting up OPTIMIZED LiteSpeed Cache..."
    wp plugin install litespeed-cache --activate --allow-root

    # Cache Settings - Moderate caching
    wp litespeed-option set cache true --allow-root
    wp litespeed-option set cache-priv false --allow-root     # DISABLED for performance
    wp litespeed-option set cache-commenter false --allow-root # DISABLED for performance
    wp litespeed-option set cache-rest false --allow-root     # DISABLED for performance
    wp litespeed-option set cache-page_login false --allow-root # DISABLED for performance
    wp litespeed-option set cache-favicon true --allow-root
    wp litespeed-option set cache-resources true --allow-root
    wp litespeed-option set cache-mobile true --allow-root
    wp litespeed-option set cache-browser true --allow-root

    # TTL Settings - Shorter times for better performance
    wp litespeed-option set cache-ttl_pub 86400 --allow-root     # 24 hours instead of 7 days
    wp litespeed-option set cache-ttl_priv 600 --allow-root     # 10 minutes instead of 30
    wp litespeed-option set cache-ttl_frontpage 86400 --allow-root # 24 hours instead of 7 days
    wp litespeed-option set cache-ttl_feed 3600 --allow-root    # 1 hour instead of 7 days

    # Purge Settings
    wp litespeed-option set purge-upgrade true --allow-root
    wp litespeed-option set purge-stale true --allow-root

    # ESI Settings - DISABLED for performance
    wp litespeed-option set esi false --allow-root             # DISABLED
    wp litespeed-option set esi-cache_admbar false --allow-root # DISABLED
    wp litespeed-option set esi-cache_commform false --allow-root # DISABLED

    # Optimization Settings - Reduced optimization
    wp litespeed-option set optm-css_min true --allow-root
    wp litespeed-option set optm-css_comb false --allow-root   # DISABLED - causes issues
    wp litespeed-option set optm-css_async false --allow-root  # DISABLED - causes issues
    wp litespeed-option set optm-js_min true --allow-root
    wp litespeed-option set optm-js_comb false --allow-root    # DISABLED - causes issues
    wp litespeed-option set optm-js_defer false --allow-root   # DISABLED - causes issues
    wp litespeed-option set optm-html_min false --allow-root   # DISABLED - performance impact
    wp litespeed-option set optm-qs_rm false --allow-root      # DISABLED - can break things
    wp litespeed-option set optm-ggfonts_rm false --allow-root # DISABLED - can break fonts

    # Media Settings - Reduced optimization
    wp litespeed-option set img_optm-auto false --allow-root   # DISABLED - performance impact
    wp litespeed-option set img_optm-webp false --allow-root   # DISABLED - can cause issues
    wp litespeed-option set media-lazy false --allow-root      # DISABLED - can cause issues
    wp litespeed-option set media-iframe_lazy false --allow-root # DISABLED

    # Crawler Settings - MUCH more conservative
    wp litespeed-option set crawler false --allow-root         # DISABLED - major performance impact
    # wp litespeed-option set crawler-usleep 1000 --allow-root # If enabled: slower crawling
    # wp litespeed-option set crawler-run_duration 60 --allow-root # If enabled: shorter runs
    # wp litespeed-option set crawler-threads 1 --allow-root   # If enabled: single thread

    # Database Optimization - Conservative
    wp litespeed-option set db_optm-revisions_max 10 --allow-root  # Reduced from 50
    wp litespeed-option set db_optm-revisions_age 7 --allow-root   # Reduced from 30

    echo "LiteSpeed Cache configured with OPTIMIZED settings for performance"
}

# Funzione per installare e configurare plugin di sicurezza
setup_security_plugins() {
    echo "Installing minimal security plugins..."
    # WP Security Audit Log - lightweight monitoring
    wp plugin install wp-security-audit-log --allow-root
}

# Funzione per installare plugin/temi di default
setup_custom_plugins() {
    echo "Installing custom plugins..."
    
    # Array di URL dei plugin da installare
    declare -a plugin_urls=(
        "https://minio-ls8g4sowggsso880wccww44c.app.rewamp.it/pluginaifb/breakdance.zip"
        "https://minio-ls8g4sowggsso880wccww44c.app.rewamp.it/pluginaifb/697144_wpmu-dev-dashboard-4.11.28.zip"
    )

    # Installa ogni plugin dall'URL
    for url in "${plugin_urls[@]}"; do
        echo "Installing plugin from: $url"
        if wp plugin install "$url" --force --allow-root; then
            echo "Successfully installed plugin from: $url"
        else
            echo "Failed to install plugin from: $url - skipping..."
        fi
    done
}

# Funzione principale di setup
main() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') Starting OPTIMIZED setup process..."
    
    # Setup ottimizzato della cache
    setup_litespeed_cache_optimized
    
    # Setup sicurezza leggera
    setup_security_plugins
    
    # Setup plugin custom
    setup_custom_plugins
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') OPTIMIZED setup completed successfully!"
}

# Esegui setup solo se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 