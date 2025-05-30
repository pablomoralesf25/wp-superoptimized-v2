# Dichiara gli ARG prima del FROM
ARG OPENLITESPEED_VERSION=1.8.2
ARG PHP_VERSION=82

FROM litespeedtech/openlitespeed:${OPENLITESPEED_VERSION}-lsphp${PHP_VERSION}

# Altri argomenti build
ARG RELAY_VERSION=v0.8.0
ARG RELAY_PHP_VERSION=8.2
ARG PLATFORM=x86-64
ARG PHP_VERSION=82
ARG WORDPRESS_VERSION=6.6.2   

# Imposta le directory PHP
ENV PHP_EXT_DIR=/usr/local/lsws/lsphp${PHP_VERSION}/lib/php/20220829
ENV PHP_INI_DIR=/usr/local/lsws/lsphp${PHP_VERSION}/etc/php/8.2/mods-available/

ENV DEBIAN_FRONTEND=noninteractive

# Install essential dependencies with maximum performance optimizations
RUN apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y && apt-get clean && \
    apt-get install -y \
    wget \
    wait-for-it \
    gettext-base \
    tzdata \
    python3.12 \
    libglib2.0-0 \
    curl \
    mysql-server \
    mysql-client \
    ghostscript \
    ca-certificates \
    gnupg \
    file \
    redis-server \
    memcached \
    htop \
    iotop \
    net-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Update CA certificates for wp_remote_get() SSL fix
RUN update-ca-certificates --fresh

# COOLIFY-SPECIFIC NETWORKING FIXES
# Install additional networking tools for Coolify environment
RUN apt-get update && apt-get install -y \
    dnsutils \
    iputils-ping \
    telnet \
    netcat-openbsd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure DNS for better resolution in Docker containers
# Note: /etc/resolv.conf is managed by Docker, so we'll configure DNS at runtime
RUN echo "# DNS will be configured at runtime in entrypoint script" > /tmp/dns-config.txt

# Create optimized directories for caching
RUN mkdir -p /tmp/opcache \
    && mkdir -p /tmp/lshttpd/cache \
    && mkdir -p /dev/shm/lscache \
    && chmod 755 /tmp/opcache \
    && chmod 755 /tmp/lshttpd/cache \
    && chmod 755 /dev/shm/lscache \
    && chown nobody:nogroup /tmp/opcache \
    && chown nobody:nogroup /tmp/lshttpd/cache \
    && chown nobody:nogroup /dev/shm/lscache

# Imposta permessi restrittivi
RUN chmod 644 /etc/apt/sources.list.d/* \
    && chmod 644 /etc/apt/sources.list

# Download Relay
RUN curl -L "https://builds.r2.relay.so/${RELAY_VERSION}/relay-${RELAY_VERSION}-php${RELAY_PHP_VERSION}-debian-${PLATFORM}+libssl3.tar.gz" | tar xz -C /tmp

# Copy relay.{so,ini} e configura secondo documentazione
RUN cp "/tmp/relay-${RELAY_VERSION}-php${RELAY_PHP_VERSION}-debian-${PLATFORM}+libssl3/relay.ini" "${PHP_INI_DIR}/60-relay.ini" \
    && cp "/tmp/relay-${RELAY_VERSION}-php${RELAY_PHP_VERSION}-debian-${PLATFORM}+libssl3/relay-pkg.so" "${PHP_EXT_DIR}/relay.so" \
    && sed -i "s/00000000-0000-0000-0000-000000000000/$(cat /proc/sys/kernel/random/uuid)/" "${PHP_EXT_DIR}/relay.so" \
    && sed -i 's/^relay.maxmemory = .*/relay.maxmemory = 128M/' "${PHP_INI_DIR}/60-relay.ini" \
    && sed -i 's/^relay.eviction_policy = .*/relay.eviction_policy = noeviction/' "${PHP_INI_DIR}/60-relay.ini" \
    && sed -i 's/^relay.environment = .*/relay.environment = production/' "${PHP_INI_DIR}/60-relay.ini" \
    && sed -i 's/^relay.databases = .*/relay.databases = 16/' "${PHP_INI_DIR}/60-relay.ini" \
    && sed -i 's/^relay.maxmemory_pct = .*/relay.maxmemory_pct = 95/' "${PHP_INI_DIR}/60-relay.ini" \
    && rm -rf /tmp/relay*

# Scarica e configura WordPress
RUN cd /var/www/vhosts/localhost/ \
    && wget https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz \
    && tar -xzf wordpress-${WORDPRESS_VERSION}.tar.gz \
    && rm wordpress-${WORDPRESS_VERSION}.tar.gz \
    && mv wordpress/* html/ \
    && rm -rf wordpress \
    && chown -R nobody:nogroup html/

# Installa WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Create scripts directory and start building entrypoint script
RUN mkdir -p /usr/local/bin/

# Create a SUPER SIMPLE entrypoint script for debugging
RUN echo '#!/bin/bash' > /usr/local/bin/docker-entrypoint.sh && \
    echo 'set -e' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Sleeping for 5 seconds to allow mounts to settle..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'sleep 5' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Initializing entrypoint script..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Running as user: $(whoami) (ID: $(id))"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Listing /usr/local/bin:"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'ls -la /usr/local/bin' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Attempting to cat /usr/local/bin/docker-entrypoint.sh:"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '[ -f "/usr/local/bin/docker-entrypoint.sh" ] && echo "DEBUG: File /usr/local/bin/docker-entrypoint.sh EXISTS. Content:" && cat /usr/local/bin/docker-entrypoint.sh || echo "DEBUG: CRITICAL - File /usr/local/bin/docker-entrypoint.sh DOES NOT EXIST at this point."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "DEBUG: ---- End of initial diagnostics ----"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo ">>>> Hello from SIMPLIFIED entrypoint! <<<<" >> /usr/local/bin/docker-entrypoint.sh' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo ">>>> Current directory: $(pwd) <<<<" >> /usr/local/bin/docker-entrypoint.sh' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo ">>>> Script path: /usr/local/bin/docker-entrypoint.sh <<<<" >> /usr/local/bin/docker-entrypoint.sh' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo ">>>> Listing /usr/local/bin (again): <<<<" >> /usr/local/bin/docker-entrypoint.sh' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'ls -la /usr/local/bin/' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo ">>>> Who am I (again): $(whoami) <<<<" >> /usr/local/bin/docker-entrypoint.sh' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo ">>>> SIMPLIFIED entrypoint finished successfully. <<<<" >> /usr/local/bin/docker-entrypoint.sh' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'exit 0' >> /usr/local/bin/docker-entrypoint.sh

# Ensure dos2unix is installed and convert the script
RUN apt-get update && apt-get install -y dos2unix && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN dos2unix /usr/local/bin/docker-entrypoint.sh

# Make entrypoint executable and verify
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
    echo "=== SHELL VERIFICATION ===" && \
    ls -l /bin/bash && \
    echo "=== ENTRYPOINT VERIFICATION ===" && \
    ls -la /usr/local/bin/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT CONTENT CHECK (FIRST 10 LINES) ===" && \
    head -10 /usr/local/bin/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT SIZE CHECK (LINES) ===" && \
    wc -l /usr/local/bin/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT SYNTAX CHECK ===" && \
    bash -n /usr/local/bin/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT READY ==="

# Set working directory
WORKDIR /var/www

# Set entrypoint
ENTRYPOINT ["/bin/bash", "/usr/local/bin/docker-entrypoint.sh"]

# Create /usr/local/bin directory if it doesn't exist
RUN mkdir -p /usr/local/bin/

# --- Create /usr/local/bin/security-setup.sh ---
RUN echo '#!/bin/bash' > /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Configurazione logging più robusta' >> /usr/local/bin/security-setup.sh && \
    echo 'if [ ! -d "/var/log/wordpress" ]; then' >> /usr/local/bin/security-setup.sh && \
    echo '    mkdir -p /var/log/wordpress' >> /usr/local/bin/security-setup.sh && \
    echo 'fi' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo 'LOGFILE="/var/log/wordpress/security-setup.log"' >> /usr/local/bin/security-setup.sh && \
    echo 'exec 1> >(tee -a "$LOGFILE") 2>&1' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting security setup script..."' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Verifichiamo che WP-CLI sia disponibile' >> /usr/local/bin/security-setup.sh && \
    echo 'if ! command -v wp &> /dev/null; then' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "ERROR: wp-cli non è installato"' >> /usr/local/bin/security-setup.sh && \
    echo '    exit 1' >> /usr/local/bin/security-setup.sh && \
    echo 'fi' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Verifichiamo che WordPress sia installato' >> /usr/local/bin/security-setup.sh && \
    echo 'if ! wp core is-installed --allow-root; then' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "ERROR: WordPress non è ancora installato"' >> /usr/local/bin/security-setup.sh && \
    echo '    exit 1' >> /usr/local/bin/security-setup.sh && \
    echo 'fi' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Verifichiamo i permessi' >> /usr/local/bin/security-setup.sh && \
    echo 'if [ ! -w "/var/www/vhosts/localhost/html" ]; then' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "ERROR: Permessi insufficienti sulla directory di WordPress"' >> /usr/local/bin/security-setup.sh && \
    echo '    exit 1' >> /usr/local/bin/security-setup.sh && \
    echo 'fi' >> /usr/local/bin/security-setup.sh

RUN echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Disabilita tutti gli aggiornamenti automatici' >> /usr/local/bin/security-setup.sh && \
    echo 'echo "Disabling automatic updates..."' >> /usr/local/bin/security-setup.sh && \
    echo 'wp config set WP_AUTO_UPDATE_CORE false --raw --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo 'wp config set AUTOMATIC_UPDATER_DISABLED true --raw --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo 'wp config set WP_AUTO_UPDATE_PLUGINS false --raw --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo 'wp config set WP_AUTO_UPDATE_THEMES false --raw --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo 'wp config set DISALLOW_FILE_MODS true --raw --allow-root  # Disabilita anche l\'installazione di plugin/temi' >> /usr/local/bin/security-setup.sh && \
    echo 'wp config set DISALLOW_FILE_EDIT true --raw --allow-root  # Disabilita l\'editor di file nel backend' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Disabilita gli aggiornamenti tramite wp-cli' >> /usr/local/bin/security-setup.sh && \
    echo 'wp config set WP_CLI_DISABLE_AUTO_CHECK_UPDATE true --raw --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo 'echo "Automatic updates disabled successfully"' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Rimuovi plugin non necessari' >> /usr/local/bin/security-setup.sh && \
    echo 'echo "Removing unnecessary plugins..."' >> /usr/local/bin/security-setup.sh && \
    echo 'wp plugin delete akismet --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo 'wp plugin delete hello --allow-root' >> /usr/local/bin/security-setup.sh

RUN echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Verifica se le variabili d'\''ambiente sono impostate' >> /usr/local/bin/security-setup.sh && \
    echo 'if [ "${ENABLE_MODSECURITY}" = "true" ]; then' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "Enabling ModSecurity..."' >> /usr/local/bin/security-setup.sh && \
    echo '    # Configurazione ModSecurity' >> /usr/local/bin/security-setup.sh && \
    echo 'fi' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo 'if [ "${ENABLE_RATE_LIMITING}" = "true" ]; then' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "Enabling Rate Limiting..."' >> /usr/local/bin/security-setup.sh && \
    echo '    # Configurazione Rate Limiting' >> /usr/local/bin/security-setup.sh && \
    echo 'fi' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo 'if [ "${ENABLE_IP_ACCESS_CONTROL}" = "true" ]; then' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "Enabling IP Access Control..."' >> /usr/local/bin/security-setup.sh && \
    echo '    # Configurazione IP Access Control' >> /usr/local/bin/security-setup.sh && \
    echo 'fi' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Rimuoviamo la parte di fail2ban da qui poiché ora è gestita dal container dedicato' >> /usr/local/bin/security-setup.sh

RUN echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Funzione per installare e configurare LiteSpeed Cache' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_litespeed_cache() {' >> /usr/local/bin/security-setup.sh && \
    echo '    wp plugin install litespeed-cache --activate --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Cache Settings' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-priv true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-commenter true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-rest true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-page_login true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-favicon true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-resources true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-mobile true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-browser true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # TTL Settings' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-ttl_pub 604800 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-ttl_priv 1800 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-ttl_frontpage 604800 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set cache-ttl_feed 604800 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Purge Settings' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set purge-upgrade true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set purge-stale true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # ESI Settings' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set esi true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set esi-cache_admbar true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set esi-cache_commform true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Optimization Settings' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-css_min true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-css_comb true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-css_async true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-js_min true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-js_comb true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-js_defer true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-html_min true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-qs_rm true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set optm-ggfonts_rm true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Media Settings' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set img_optm-auto true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set img_optm-webp true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set media-lazy true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set media-iframe_lazy true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Crawler Settings' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set crawler true --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set crawler-usleep 500 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set crawler-run_duration 400 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set crawler-threads 3 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Database Optimization' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set db_optm-revisions_max 50 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '    wp litespeed-option set db_optm-revisions_age 30 --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '}' >> /usr/local/bin/security-setup.sh

RUN echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Funzione per installare e configurare plugin di sicurezza' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_security_plugins() {' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # WP Security Audit Log' >> /usr/local/bin/security-setup.sh && \
    echo '    wp plugin install wp-security-audit-log --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '}' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Funzione per installare e configurare plugin di ottimizzazione' >> /usr/local/bin/security-setup.sh && \
    echo '#setup_optimization_plugins() {}' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Funzione per installare plugin/temi di default' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_custom_plugins() {' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "Installing custom plugins..."' >> /usr/local/bin/security-setup.sh && \
    echo '    ' >> /usr/local/bin/security-setup.sh && \
    echo '    # Array di URL dei plugin da installare' >> /usr/local/bin/security-setup.sh && \
    echo '    declare -a plugin_urls=(' >> /usr/local/bin/security-setup.sh && \
    echo '        "https://minio-ls8g4sowggsso880wccww44c.app.rewamp.it/pluginaifb/breakdance.zip"  # Breakdance' >> /usr/local/bin/security-setup.sh && \
    echo '        "https://minio-ls8g4sowggsso880wccww44c.app.rewamp.it/pluginaifb/697144_wpmu-dev-dashboard-4.11.28.zip"  # WPMUDEV DASHBOARD' >> /usr/local/bin/security-setup.sh && \
    echo '        # Aggiungi altri URL qui' >> /usr/local/bin/security-setup.sh && \
    echo '    )' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Installa ogni plugin dall'\''URL' >> /usr/local/bin/security-setup.sh && \
    echo '    for url in "${plugin_urls[@]}"; do' >> /usr/local/bin/security-setup.sh && \
    echo '        echo "Installing plugin from: $url"' >> /usr/local/bin/security-setup.sh && \
    echo '        if wp plugin install "$url" --force --allow-root; then' >> /usr/local/bin/security-setup.sh && \
    echo '            echo "Successfully installed plugin from: $url"' >> /usr/local/bin/security-setup.sh && \
    echo '        else' >> /usr/local/bin/security-setup.sh && \
    echo '            echo "Failed to install plugin from: $url - skipping..."' >> /usr/local/bin/security-setup.sh && \
    echo '        fi' >> /usr/local/bin/security-setup.sh && \
    echo '    done' >> /usr/local/bin/security-setup.sh && \
    echo '}' >> /usr/local/bin/security-setup.sh

RUN echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Funzione per installare e configurare temi' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_custom_themes() {' >> /usr/local/bin/security-setup.sh && \
    echo '    echo "Installing custom themes..."' >> /usr/local/bin/security-setup.sh && \
    echo '    ' >> /usr/local/bin/security-setup.sh && \
    echo '    # Array di URL dei temi da installare' >> /usr/local/bin/security-setup.sh && \
    echo '    declare -a theme_urls=(' >> /usr/local/bin/security-setup.sh && \
    echo '        "https://minio-ls8g4sowggsso880wccww44c.app.rewamp.it/pluginaifb/breakdance-zero-theme-master.zip"  # breakdance zero theme' >> /usr/local/bin/security-setup.sh && \
    echo '        # Aggiungi altri URL qui' >> /usr/local/bin/security-setup.sh && \
    echo '    )' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '    # Installa ogni tema dall'\''URL' >> /usr/local/bin/security-setup.sh && \
    echo '    for url in "${theme_urls[@]}"; do' >> /usr/local/bin/security-setup.sh && \
    echo '        echo "Installing theme from: $url"' >> /usr/local/bin/security-setup.sh && \
    echo '        if wp theme install "$url" --force --allow-root; then' >> /usr/local/bin/security-setup.sh && \
    echo '            echo "Successfully installed theme from: $url"' >> /usr/local/bin/security-setup.sh && \
    echo '        else' >> /usr/local/bin/security-setup.sh && \
    echo '            echo "Failed to install theme from: $url - skipping..."' >> /usr/local/bin/security-setup.sh && \
    echo '        fi' >> /usr/local/bin/security-setup.sh && \
    echo '    done' >> /usr/local/bin/security-setup.sh && \
    echo '}' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Esegui le configurazioni' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_litespeed_cache' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_security_plugins' >> /usr/local/bin/security-setup.sh && \
    echo '#setup_optimization_plugins() {}' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_custom_plugins' >> /usr/local/bin/security-setup.sh && \
    echo 'setup_custom_themes' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo '# Pulisci la cache dopo le installazioni' >> /usr/local/bin/security-setup.sh && \
    echo 'wp cache flush --allow-root' >> /usr/local/bin/security-setup.sh && \
    echo '' >> /usr/local/bin/security-setup.sh && \
    echo 'echo "Security setup completed successfully!"' >> /usr/local/bin/security-setup.sh

# --- Placeholder for docker-entrypoint.sh creation ---
# --- We will add this in the next step --- 

# Ensure dos2unix is installed (should be from earlier layer, but belt-and-suspenders)
# RUN apt-get update && apt-get install -y dos2unix && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN dos2unix /usr/local/bin/security-setup.sh
# RUN dos2unix /usr/local/bin/docker-entrypoint.sh # Will add this back later

# Copy performance monitoring script and make executable
COPY scripts/performance-monitor.sh /usr/local/bin/performance-monitor.sh
RUN chmod +x /usr/local/bin/performance-monitor.sh

# Copy optimization files
COPY config/httpd_config.conf /usr/local/lsws/conf/httpd_config.conf
COPY config/wp-config-optimizations.php /tmp/wp-config-optimizations.php
COPY config/coolify-wp-remote-get-fix.php /tmp/coolify-wp-remote-get-fix.php

# Make entrypoints executable and verify (simplified verification now)
RUN chmod +x /usr/local/bin/security-setup.sh && \
    # chmod +x /usr/local/bin/docker-entrypoint.sh && # Will add this back later
    echo "=== SHELL VERIFICATION ===" && \
    ls -l /bin/bash && \
    # echo "=== ENTRYPOINT VERIFICATION (/usr/local/bin/docker-entrypoint.sh) ===" && # Will add this back later
    # ls -la /usr/local/bin/docker-entrypoint.sh && # Will add this back later
    # bash -n /usr/local/bin/docker-entrypoint.sh && # Will add this back later
    echo "=== SECURITY SCRIPT VERIFICATION (/usr/local/bin/security-setup.sh) ===" && \
    ls -la /usr/local/bin/security-setup.sh && \
    bash -n /usr/local/bin/security-setup.sh && \
    echo "=== PERFORMANCE MONITOR VERIFICATION ===" && \
    ls -la /usr/local/bin/performance-monitor.sh && \
    bash -n /usr/local/bin/performance-monitor.sh && \
    echo "=== SCRIPTS READY ==="

# Set working directory
WORKDIR /var/www

# Set entrypoint (temporary, will be changed)
# ENTRYPOINT ["/bin/bash", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"] # Temporary CMD to keep container running for checks

# --- Create /usr/local/bin/docker-entrypoint.sh ---
RUN echo '#!/bin/bash' > /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Configurazione logging' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'LOGFILE="/var/log/wordpress/entrypoint.log"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'mkdir -p /var/log/wordpress' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'exec 1> >(tee -a "$LOGFILE") 2>&1' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Creiamo il socket per il logging se non esiste' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ ! -d "/dev" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    mkdir -p /dev' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ ! -S "/dev/log" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    mkfifo /dev/log' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Funzione per verificare lo stato di OpenLiteSpeed' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'check_litespeed() {' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    if ! pgrep litespeed > /dev/null; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') ERROR: OpenLiteSpeed non è in esecuzione!"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        return 1' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    return 0' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '}' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Copy custom php.ini if provided' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ -f "/tmp/host-php.ini" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Copying custom php.ini configuration..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    mkdir -p "/usr/local/lsws/lsphp${PHP_VERSION}/etc/php/8.2/litespeed/"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    cp "/tmp/host-php.ini" "/usr/local/lsws/lsphp${PHP_VERSION}/etc/php/8.2/litespeed/php.ini"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Custom php.ini copied successfully"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# MAXIMUM PERFORMANCE OPTIMIZATIONS' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Applying maximum performance optimizations..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Update CA certificates for wp_remote_get() fix' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Updating CA certificates for wp_remote_get() SSL fix..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'update-ca-certificates --fresh' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Set up RAM disk for cache if not exists' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ ! -d "/dev/shm/lscache" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    mkdir -p /dev/shm/lscache' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    chown nobody:nogroup /dev/shm/lscache' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    chmod 755 /dev/shm/lscache' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') RAM disk cache directory created"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Optimize system settings for maximum performance (one-time only)' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ ! -f "/tmp/.sysctl-configured" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Optimizing system settings..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "net.ipv4.tcp_rmem = 4096 87380 16777216" >> /etc/sysctl.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "net.ipv4.tcp_wmem = 4096 65536 16777216" >> /etc/sysctl.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    sysctl -p /etc/sysctl.conf 2>/dev/null || true' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    touch /tmp/.sysctl-configured' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "System settings optimized"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'else' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "System settings already optimized"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Start Redis for object caching (if not already running)' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if ! pgrep redis-server > /dev/null; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting Redis server..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    redis-server --daemonize yes --maxmemory 256mb --maxmemory-policy allkeys-lru' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'else' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "Redis server already running"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Start Memcached for additional caching (if not already running)' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if ! pgrep memcached > /dev/null; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting Memcached server..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    memcached -d -m 128 -p 11211 -u nobody' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'else' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "Memcached server already running"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Performance optimizations applied successfully"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# COOLIFY-SPECIFIC NETWORKING FIXES' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Applying Coolify networking fixes..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Configure DNS for better resolution (runtime configuration)' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "Configuring DNS for container networking..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ -w /etc/resolv.conf ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "nameserver 8.8.8.8" >> /etc/resolv.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "nameserver 8.8.4.4" >> /etc/resolv.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "nameserver 1.1.1.1" >> /etc/resolv.conf' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "DNS configuration updated"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'else' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "DNS managed by Docker, using default configuration"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Test DNS resolution' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "Testing DNS resolution..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'nslookup api.wordpress.org || echo "DNS resolution test failed"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Test external connectivity' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "Testing external connectivity..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'curl -I --connect-timeout 10 https://api.wordpress.org/core/version-check/1.7/ || echo "External connectivity test failed"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Copy Coolify wp_remote_get() fixes to WordPress' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ -f "/tmp/coolify-wp-remote-get-fix.php" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    mkdir -p /var/www/vhosts/localhost/html/wp-content/mu-plugins/' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    cp /tmp/coolify-wp-remote-get-fix.php /var/www/vhosts/localhost/html/wp-content/mu-plugins/' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    chown -R nobody:nogroup /var/www/vhosts/localhost/html/wp-content/mu-plugins/' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "Coolify wp_remote_get() fixes applied to mu-plugins"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'else' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "Coolify wp_remote_get() fix file not found"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Coolify networking fixes applied successfully"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Attendiamo che MySQL sia pronto' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'until mysqladmin ping -h"$WORDPRESS_DB_HOST" --silent; do' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Waiting for MySQL to be ready..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    sleep 2' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'done' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Imposta il percorso corretto per WordPress' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'cd /var/www/vhosts/localhost/html' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Installiamo WordPress se non è già installato' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if ! wp core is-installed --allow-root; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Installing WordPress..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    wp core install \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --url="$SITE_URL" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --title="$SITE_TITLE" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --admin_user="$ADMIN_USER" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --admin_password="$ADMIN_PASSWORD" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --admin_email="$ADMIN_EMAIL" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --dbhost="$WORDPRESS_DB_HOST" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --dbname="$WORDPRESS_DB_NAME" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --dbuser="$WORDPRESS_DB_USER" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --dbpass="$WORDPRESS_DB_PASSWORD" \\' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        --allow-root' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Configure OpenLiteSpeed admin credentials' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ ! -f "/usr/local/lsws/admin/conf/htpasswd" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Configuring OpenLiteSpeed admin credentials..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    # Create admin user' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    /usr/local/lsws/admin/misc/admpass.sh << EOF' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '${OLS_ADMIN_USERNAME}' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '${OLS_ADMIN_PASSWORD}' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '${OLS_ADMIN_PASSWORD}' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'EOF' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "OpenLiteSpeed admin credentials configured."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Verifica e correggi i permessi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Checking and fixing permissions..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'chown -R nobody:nogroup /usr/local/lsws/conf/' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'chmod -R 755 /usr/local/lsws/conf/' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'chown -R nobody:nogroup /var/www/vhosts/localhost/html/' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'chmod -R 755 /var/www/vhosts/localhost/html/' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Eseguiamo il setup di sicurezza una sola volta' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if [ ! -f "/var/www/security-setup.done" ]; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Running security setup..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    if bash /usr/local/bin/security-setup.sh; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        touch /var/www/security-setup.done' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Security setup completed successfully."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    else' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') WARNING: Security setup failed!"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Avviamo OpenLiteSpeed' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Launching OpenLiteSpeed..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '/usr/local/lsws/bin/lswsctrl start' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Verifica iniziale' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'sleep 5' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'if ! check_litespeed; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') ERROR: OpenLiteSpeed failed to start properly!"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    exit 1' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'fi' >> /usr/local/bin/docker-entrypoint.sh

RUN echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Monitora OpenLiteSpeed' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'while true; do' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    if ! check_litespeed; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') WARNING: OpenLiteSpeed crashed, attempting restart..."' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        /usr/local/lsws/bin/lswsctrl restart' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        sleep 5' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        if ! check_litespeed; then' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '            echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') CRITICAL: OpenLiteSpeed failed to restart!"' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '            exit 1' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '        fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    fi' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '    sleep 10' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'done' >> /usr/local/bin/docker-entrypoint.sh

# (Keep existing dos2unix for security-setup.sh)
RUN dos2unix /usr/local/bin/docker-entrypoint.sh # Add dos2unix for the main entrypoint

# (Keep existing chmod +x for security-setup.sh)
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT VERIFICATION (/usr/local/bin/docker-entrypoint.sh) ===" && \
    ls -la /usr/local/bin/docker-entrypoint.sh && \
    bash -n /usr/local/bin/docker-entrypoint.sh && \
    echo "=== MAIN ENTRYPOINT SCRIPT READY ==="

# (Keep WORKDIR /var/www)

# Final ENTRYPOINT
ENTRYPOINT ["/bin/bash", "/usr/local/bin/docker-entrypoint.sh"]
