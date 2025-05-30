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

# Installa dipendenze essenziali
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

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

# Create scripts directory and embed entrypoint script directly
RUN mkdir -p /var/www/scripts/ && \
    cat > /var/www/scripts/docker-entrypoint.sh << 'EOF'
#!/bin/bash

# Configurazione logging
LOGFILE="/var/log/wordpress/entrypoint.log"
mkdir -p /var/log/wordpress
exec 1> >(tee -a "$LOGFILE") 2>&1

# Creiamo il socket per il logging se non esiste
if [ ! -d "/dev" ]; then
    mkdir -p /dev
fi
if [ ! -S "/dev/log" ]; then
    mkfifo /dev/log
fi

# Funzione per verificare lo stato di OpenLiteSpeed
check_litespeed() {
    if ! pgrep litespeed > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: OpenLiteSpeed non è in esecuzione!"
        return 1
    fi
    return 0
}

# Copy custom php.ini if provided
if [ -f "/tmp/host-php.ini" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Copying custom php.ini configuration..."
    mkdir -p "/usr/local/lsws/lsphp${PHP_VERSION}/etc/php/8.2/litespeed/"
    cp "/tmp/host-php.ini" "/usr/local/lsws/lsphp${PHP_VERSION}/etc/php/8.2/litespeed/php.ini"
    echo "$(date '+%Y-%m-%d %H:%M:%S') Custom php.ini copied successfully"
fi

# Attendiamo che MySQL sia pronto
until mysqladmin ping -h"$WORDPRESS_DB_HOST" --silent; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') Starting up: Waiting for MySQL to be ready..."
    sleep 2
done

# Imposta il percorso corretto per WordPress
cd /var/www/vhosts/localhost/html

# Installiamo WordPress se non è già installato
if ! wp core is-installed --allow-root; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Starting up: Installing WordPress..."
    wp core install \
        --url="$SITE_URL" \
        --title="$SITE_TITLE" \
        --admin_user="$ADMIN_USER" \
        --admin_password="$ADMIN_PASSWORD" \
        --admin_email="$ADMIN_EMAIL" \
        --allow-root
fi

# Configure OpenLiteSpeed admin credentials
if [ ! -f "/usr/local/lsws/admin/conf/htpasswd" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Starting up: Configuring OpenLiteSpeed admin credentials..."
    # Create admin user
    /usr/local/lsws/admin/misc/admpass.sh << SUBEOF
${OLS_ADMIN_USERNAME}
${OLS_ADMIN_PASSWORD}
${OLS_ADMIN_PASSWORD}
SUBEOF
    echo "OpenLiteSpeed admin credentials configured."
fi

# Verifica e correggi i permessi
echo "$(date '+%Y-%m-%d %H:%M:%S') Checking and fixing permissions..."
chown -R nobody:nogroup /usr/local/lsws/conf/
chmod -R 755 /usr/local/lsws/conf/
chown -R nobody:nogroup /var/www/vhosts/localhost/html/
chmod -R 755 /var/www/vhosts/localhost/html/

# Simplified security setup (embedded)
echo "$(date '+%Y-%m-%d %H:%M:%S') Starting up: Running security setup..."
if [ ! -f "/var/www/security-setup.done" ]; then
    # Basic security hardening
    chmod 644 /etc/passwd /etc/group
    find /var/www/vhosts/localhost/html -type d -exec chmod 755 {} \;
    find /var/www/vhosts/localhost/html -type f -exec chmod 644 {} \;
    touch /var/www/security-setup.done
    echo "$(date '+%Y-%m-%d %H:%M:%S') Security setup completed successfully."
fi

# Avviamo OpenLiteSpeed
echo "$(date '+%Y-%m-%d %H:%M:%S') Starting up: Launching OpenLiteSpeed..."
/usr/local/lsws/bin/lswsctrl start

# Verifica iniziale
sleep 5
if ! check_litespeed; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: OpenLiteSpeed failed to start properly!"
    exit 1
fi

# Monitora OpenLiteSpeed
while true; do
    if ! check_litespeed; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: OpenLiteSpeed crashed, attempting restart..."
        /usr/local/lsws/bin/lswsctrl restart
        sleep 5
        if ! check_litespeed; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') CRITICAL: OpenLiteSpeed failed to restart!"
            exit 1
        fi
    fi
    sleep 10
done
EOF

# Make entrypoint executable and verify
RUN chmod +x /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT VERIFICATION ===" && \
    ls -la /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT CONTENT CHECK ===" && \
    head -5 /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT READY ===" 

# Set working directory
WORKDIR /var/www

# Set entrypoint
ENTRYPOINT ["/var/www/scripts/docker-entrypoint.sh"]
CMD ["/usr/local/lsws/bin/lswsctrl", "start", "-n"]
