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

# Create scripts directory and start building entrypoint script
RUN mkdir -p /var/www/scripts/

# Create the shebang and logging setup
RUN echo '#!/bin/bash' > /var/www/scripts/docker-entrypoint.sh && \
    echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Configurazione logging' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'LOGFILE="/var/log/wordpress/entrypoint.log"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'mkdir -p /var/log/wordpress' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'exec 1> >(tee -a "$LOGFILE") 2>&1' >> /var/www/scripts/docker-entrypoint.sh

# Add logging socket setup
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Creiamo il socket per il logging se non esiste' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'if [ ! -d "/dev" ]; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    mkdir -p /dev' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'fi' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'if [ ! -S "/dev/log" ]; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    mkfifo /dev/log' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'fi' >> /var/www/scripts/docker-entrypoint.sh

# Add check_litespeed function
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Funzione per verificare lo stato di OpenLiteSpeed' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'check_litespeed() {' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    if ! pgrep litespeed > /dev/null; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') ERROR: OpenLiteSpeed non è in esecuzione!"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        return 1' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    fi' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    return 0' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '}' >> /var/www/scripts/docker-entrypoint.sh

# Add PHP ini setup
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Copy custom php.ini if provided' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'if [ -f "/tmp/host-php.ini" ]; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Copying custom php.ini configuration..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    mkdir -p "/usr/local/lsws/lsphp${PHP_VERSION}/etc/php/8.2/litespeed/"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    cp "/tmp/host-php.ini" "/usr/local/lsws/lsphp${PHP_VERSION}/etc/php/8.2/litespeed/php.ini"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Custom php.ini copied successfully"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'fi' >> /var/www/scripts/docker-entrypoint.sh

# Add MySQL wait logic
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Attendiamo che MySQL sia pronto' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'until mysqladmin ping -h"$WORDPRESS_DB_HOST" --silent; do' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Waiting for MySQL to be ready..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    sleep 2' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'done' >> /var/www/scripts/docker-entrypoint.sh

# Add WordPress installation
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Imposta il percorso corretto per WordPress' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'cd /var/www/vhosts/localhost/html' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Installiamo WordPress se non è già installato' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'if ! wp core is-installed --allow-root; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Installing WordPress..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    wp core install \' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        --url="$SITE_URL" \' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        --title="$SITE_TITLE" \' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        --admin_user="$ADMIN_USER" \' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        --admin_password="$ADMIN_PASSWORD" \' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        --admin_email="$ADMIN_EMAIL" \' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        --allow-root' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'fi' >> /var/www/scripts/docker-entrypoint.sh

# Add OpenLiteSpeed admin setup
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Configure OpenLiteSpeed admin credentials' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'if [ ! -f "/usr/local/lsws/admin/conf/htpasswd" ]; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Configuring OpenLiteSpeed admin credentials..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    # Create admin user' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    /usr/local/lsws/admin/misc/admpass.sh << SUBEOF' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '${OLS_ADMIN_USERNAME}' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '${OLS_ADMIN_PASSWORD}' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '${OLS_ADMIN_PASSWORD}' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'SUBEOF' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "OpenLiteSpeed admin credentials configured."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'fi' >> /var/www/scripts/docker-entrypoint.sh

# Add permissions and security setup
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Verifica e correggi i permessi' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Checking and fixing permissions..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'chown -R nobody:nogroup /usr/local/lsws/conf/' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'chmod -R 755 /usr/local/lsws/conf/' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'chown -R nobody:nogroup /var/www/vhosts/localhost/html/' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'chmod -R 755 /var/www/vhosts/localhost/html/' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Simplified security setup (embedded)' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Running security setup..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'if [ ! -f "/var/www/security-setup.done" ]; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    # Basic security hardening' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    chmod 644 /etc/passwd /etc/group' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    find /var/www/vhosts/localhost/html -type d -exec chmod 755 {} \;' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    find /var/www/vhosts/localhost/html -type f -exec chmod 644 {} \;' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    touch /var/www/security-setup.done' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Security setup completed successfully."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'fi' >> /var/www/scripts/docker-entrypoint.sh

# Add OpenLiteSpeed startup and monitoring
RUN echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Avviamo OpenLiteSpeed' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') Starting up: Launching OpenLiteSpeed..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '/usr/local/lsws/bin/lswsctrl start' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Verifica iniziale' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'sleep 5' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'if ! check_litespeed; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') ERROR: OpenLiteSpeed failed to start properly!"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    exit 1' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'fi' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '# Monitora OpenLiteSpeed' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'while true; do' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    if ! check_litespeed; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') WARNING: OpenLiteSpeed crashed, attempting restart..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        /usr/local/lsws/bin/lswsctrl restart' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        sleep 5' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        if ! check_litespeed; then' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '            echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') CRITICAL: OpenLiteSpeed failed to restart!"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '            exit 1' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '        fi' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    fi' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '    sleep 10' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'done' >> /var/www/scripts/docker-entrypoint.sh

# Make entrypoint executable and verify
RUN chmod +x /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT VERIFICATION ===" && \
    ls -la /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT CONTENT CHECK ===" && \
    head -10 /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT SIZE CHECK ===" && \
    wc -l /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT READY ==="

# Set working directory
WORKDIR /var/www

# Set entrypoint
ENTRYPOINT ["/var/www/scripts/docker-entrypoint.sh"]
