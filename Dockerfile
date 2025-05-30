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

# Create a SUPER SIMPLE entrypoint script for debugging
RUN echo '#!/bin/bash' > /var/www/scripts/docker-entrypoint.sh && \
    echo 'set -e' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Sleeping for 5 seconds to allow mounts to settle..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'sleep 5' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Initializing entrypoint script..."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Running as user: $(whoami) (ID: $(id))"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Listing /:"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'ls -la /' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Listing /var:"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'ls -la /var' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Listing /var/www:"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'ls -la /var/www' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Listing /var/www/scripts:"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'ls -la /var/www/scripts' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: Attempting to cat /var/www/scripts/docker-entrypoint.sh:"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo '[ -f "/var/www/scripts/docker-entrypoint.sh" ] && echo "DEBUG: File /var/www/scripts/docker-entrypoint.sh EXISTS. Content:" && cat /var/www/scripts/docker-entrypoint.sh || echo "DEBUG: CRITICAL - File /var/www/scripts/docker-entrypoint.sh DOES NOT EXIST at this point."' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo "DEBUG: ---- End of initial diagnostics ----"' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo ">>>> Hello from SIMPLIFIED entrypoint! <<<<" >> /var/www/scripts/docker-entrypoint.sh' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo ">>>> Current directory: $(pwd) <<<<" >> /var/www/scripts/docker-entrypoint.sh' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo ">>>> Script path: /var/www/scripts/docker-entrypoint.sh <<<<" >> /var/www/scripts/docker-entrypoint.sh' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo ">>>> Listing /var/www/scripts (again): <<<<" >> /var/www/scripts/docker-entrypoint.sh' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'ls -la /var/www/scripts/' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo ">>>> Who am I (again): $(whoami) <<<<" >> /var/www/scripts/docker-entrypoint.sh' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'echo ">>>> SIMPLIFIED entrypoint finished successfully. <<<<" >> /var/www/scripts/docker-entrypoint.sh' >> /var/www/scripts/docker-entrypoint.sh && \
    echo 'exit 0' >> /var/www/scripts/docker-entrypoint.sh

# Ensure dos2unix is installed and convert the script
RUN apt-get update && apt-get install -y dos2unix && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN dos2unix /var/www/scripts/docker-entrypoint.sh

# Make entrypoint executable and verify
RUN chmod +x /var/www/scripts/docker-entrypoint.sh && \
    echo "=== SHELL VERIFICATION ===" && \
    ls -l /bin/bash && \
    echo "=== ENTRYPOINT VERIFICATION ===" && \
    ls -la /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT CONTENT CHECK (FIRST 10 LINES) ===" && \
    head -10 /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT SIZE CHECK (LINES) ===" && \
    wc -l /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT SYNTAX CHECK ===" && \
    bash -n /var/www/scripts/docker-entrypoint.sh && \
    echo "=== ENTRYPOINT READY ==="

# Set working directory
WORKDIR /var/www

# Set entrypoint
ENTRYPOINT ["/bin/bash", "/var/www/scripts/docker-entrypoint.sh"]
