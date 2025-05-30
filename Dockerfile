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

# Create scripts directory FIRST
RUN mkdir -p /var/www/scripts/

# Copy scripts with explicit verification
COPY scripts/ /var/www/scripts/

# Debug: Verify what was copied
RUN echo "=== DEBUG: Listing /var/www/scripts/ contents ===" \
    && ls -la /var/www/scripts/ \
    && echo "=== DEBUG: Checking specific files ===" \
    && [ -f /var/www/scripts/docker-entrypoint.sh ] && echo "✓ docker-entrypoint.sh exists" || echo "✗ docker-entrypoint.sh missing" \
    && [ -f /var/www/scripts/security-setup.sh ] && echo "✓ security-setup.sh exists" || echo "✗ security-setup.sh missing" \
    && [ -f /var/www/scripts/owaspctl.sh ] && echo "✓ owaspctl.sh exists" || echo "✗ owaspctl.sh missing"

# Make all scripts executable
RUN chmod +x /var/www/scripts/*.sh

# Verify scripts are executable and readable
RUN echo "=== DEBUG: Verifying script permissions ===" \
    && ls -la /var/www/scripts/ \
    && echo "=== DEBUG: Testing entrypoint script ===" \
    && [ -x /var/www/scripts/docker-entrypoint.sh ] && echo "✓ docker-entrypoint.sh is executable" || echo "✗ docker-entrypoint.sh not executable" \
    && echo "=== DEBUG: Script content check ===" \
    && head -5 /var/www/scripts/docker-entrypoint.sh

# Set working directory
WORKDIR /var/www

# Final verification before setting entrypoint
RUN echo "=== FINAL DEBUG: Entrypoint verification ===" \
    && test -f /var/www/scripts/docker-entrypoint.sh && echo "✓ Entrypoint file exists" || (echo "✗ Entrypoint file missing!" && exit 1) \
    && test -x /var/www/scripts/docker-entrypoint.sh && echo "✓ Entrypoint is executable" || (echo "✗ Entrypoint not executable!" && exit 1) \
    && file /var/www/scripts/docker-entrypoint.sh \
    && echo "=== Entrypoint setup complete ==="

# Set entrypoint
ENTRYPOINT ["/var/www/scripts/docker-entrypoint.sh"]
CMD ["/usr/local/lsws/bin/lswsctrl", "start", "-n"]
