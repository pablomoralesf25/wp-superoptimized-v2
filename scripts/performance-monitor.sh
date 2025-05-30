#!/bin/bash

#
# WORDPRESS PERFORMANCE MONITORING SCRIPT
# Monitors server performance and provides optimization recommendations
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/wordpress/performance-monitor.log"
mkdir -p /var/log/wordpress

echo "========================================" | tee -a "$LOG_FILE"
echo "WordPress Performance Monitor - $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Function to check service status
check_service() {
    local service=$1
    local port=$2
    
    if pgrep "$service" > /dev/null; then
        echo -e "${GREEN}✓${NC} $service is running" | tee -a "$LOG_FILE"
        if [ ! -z "$port" ]; then
            if netstat -tuln | grep ":$port " > /dev/null; then
                echo -e "  ${GREEN}✓${NC} Port $port is listening" | tee -a "$LOG_FILE"
            else
                echo -e "  ${RED}✗${NC} Port $port is not listening" | tee -a "$LOG_FILE"
            fi
        fi
        return 0
    else
        echo -e "${RED}✗${NC} $service is not running" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Function to check memory usage
check_memory() {
    echo -e "\n${BLUE}Memory Usage:${NC}" | tee -a "$LOG_FILE"
    
    # Total memory
    total_mem=$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')
    used_mem=$(free -m | awk 'NR==2{printf "%.1f", $3/1024}')
    free_mem=$(free -m | awk 'NR==2{printf "%.1f", $4/1024}')
    mem_percent=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    
    echo "  Total: ${total_mem}GB | Used: ${used_mem}GB | Free: ${free_mem}GB | Usage: ${mem_percent}%" | tee -a "$LOG_FILE"
    
    if (( $(echo "$mem_percent > 80" | bc -l) )); then
        echo -e "  ${RED}⚠${NC} High memory usage detected!" | tee -a "$LOG_FILE"
    elif (( $(echo "$mem_percent > 60" | bc -l) )); then
        echo -e "  ${YELLOW}⚠${NC} Moderate memory usage" | tee -a "$LOG_FILE"
    else
        echo -e "  ${GREEN}✓${NC} Memory usage is optimal" | tee -a "$LOG_FILE"
    fi
}

# Function to check CPU usage
check_cpu() {
    echo -e "\n${BLUE}CPU Usage:${NC}" | tee -a "$LOG_FILE"
    
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    echo "  CPU Usage: ${cpu_usage}% | Load Average: ${load_avg}" | tee -a "$LOG_FILE"
    
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        echo -e "  ${RED}⚠${NC} High CPU usage detected!" | tee -a "$LOG_FILE"
    elif (( $(echo "$cpu_usage > 60" | bc -l) )); then
        echo -e "  ${YELLOW}⚠${NC} Moderate CPU usage" | tee -a "$LOG_FILE"
    else
        echo -e "  ${GREEN}✓${NC} CPU usage is optimal" | tee -a "$LOG_FILE"
    fi
}

# Function to check disk usage
check_disk() {
    echo -e "\n${BLUE}Disk Usage:${NC}" | tee -a "$LOG_FILE"
    
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    
    echo "  Root partition: ${disk_usage}% used | ${disk_free} free" | tee -a "$LOG_FILE"
    
    if [ "$disk_usage" -gt 90 ]; then
        echo -e "  ${RED}⚠${NC} Critical disk usage!" | tee -a "$LOG_FILE"
    elif [ "$disk_usage" -gt 80 ]; then
        echo -e "  ${YELLOW}⚠${NC} High disk usage" | tee -a "$LOG_FILE"
    else
        echo -e "  ${GREEN}✓${NC} Disk usage is optimal" | tee -a "$LOG_FILE"
    fi
}

# Function to check network connections
check_network() {
    echo -e "\n${BLUE}Network Connections:${NC}" | tee -a "$LOG_FILE"
    
    established=$(netstat -an | grep ESTABLISHED | wc -l)
    time_wait=$(netstat -an | grep TIME_WAIT | wc -l)
    
    echo "  Established: $established | TIME_WAIT: $time_wait" | tee -a "$LOG_FILE"
    
    if [ "$established" -gt 1000 ]; then
        echo -e "  ${YELLOW}⚠${NC} High number of connections" | tee -a "$LOG_FILE"
    else
        echo -e "  ${GREEN}✓${NC} Connection count is normal" | tee -a "$LOG_FILE"
    fi
}

# Function to check cache performance
check_cache() {
    echo -e "\n${BLUE}Cache Status:${NC}" | tee -a "$LOG_FILE"
    
    # Check OPcache
    if php -m | grep -i opcache > /dev/null; then
        echo -e "  ${GREEN}✓${NC} OPcache is enabled" | tee -a "$LOG_FILE"
    else
        echo -e "  ${RED}✗${NC} OPcache is not enabled" | tee -a "$LOG_FILE"
    fi
    
    # Check Redis
    if check_service "redis-server" "6379" > /dev/null; then
        redis_memory=$(redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
        echo "  Redis memory usage: $redis_memory" | tee -a "$LOG_FILE"
    fi
    
    # Check Memcached
    if check_service "memcached" "11211" > /dev/null; then
        echo -e "  ${GREEN}✓${NC} Memcached is running" | tee -a "$LOG_FILE"
    fi
    
    # Check LiteSpeed Cache directory
    if [ -d "/dev/shm/lscache" ]; then
        cache_size=$(du -sh /dev/shm/lscache 2>/dev/null | cut -f1)
        echo "  LiteSpeed cache size: $cache_size" | tee -a "$LOG_FILE"
    fi
}

# Function to check WordPress performance
check_wordpress() {
    echo -e "\n${BLUE}WordPress Status:${NC}" | tee -a "$LOG_FILE"
    
    if [ -f "/var/www/vhosts/localhost/html/wp-config.php" ]; then
        echo -e "  ${GREEN}✓${NC} WordPress is installed" | tee -a "$LOG_FILE"
        
        # Check if wp_remote_get works
        cd /var/www/vhosts/localhost/html
        if wp eval "wp_remote_get('https://api.wordpress.org/core/version-check/1.7/');" --allow-root > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} wp_remote_get() is working" | tee -a "$LOG_FILE"
        else
            echo -e "  ${RED}✗${NC} wp_remote_get() is not working" | tee -a "$LOG_FILE"
        fi
        
        # Check active plugins
        plugin_count=$(wp plugin list --status=active --allow-root --format=count 2>/dev/null || echo "0")
        echo "  Active plugins: $plugin_count" | tee -a "$LOG_FILE"
        
        # Check if LiteSpeed Cache is active
        if wp plugin is-active litespeed-cache --allow-root 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} LiteSpeed Cache plugin is active" | tee -a "$LOG_FILE"
        else
            echo -e "  ${YELLOW}⚠${NC} LiteSpeed Cache plugin is not active" | tee -a "$LOG_FILE"
        fi
    else
        echo -e "  ${RED}✗${NC} WordPress is not installed" | tee -a "$LOG_FILE"
    fi
}

# Function to provide optimization recommendations
provide_recommendations() {
    echo -e "\n${BLUE}Optimization Recommendations:${NC}" | tee -a "$LOG_FILE"
    
    # Memory recommendations
    mem_percent=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    if (( $(echo "$mem_percent > 80" | bc -l) )); then
        echo "  • Consider increasing server memory or optimizing memory usage" | tee -a "$LOG_FILE"
        echo "  • Review PHP memory_limit and opcache settings" | tee -a "$LOG_FILE"
    fi
    
    # CPU recommendations
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        echo "  • Consider upgrading CPU or optimizing code" | tee -a "$LOG_FILE"
        echo "  • Enable more aggressive caching" | tee -a "$LOG_FILE"
    fi
    
    # Cache recommendations
    if ! pgrep "redis-server" > /dev/null; then
        echo "  • Enable Redis for object caching" | tee -a "$LOG_FILE"
    fi
    
    if ! php -m | grep -i opcache > /dev/null; then
        echo "  • Enable OPcache for PHP acceleration" | tee -a "$LOG_FILE"
    fi
    
    # WordPress specific recommendations
    if [ -f "/var/www/vhosts/localhost/html/wp-config.php" ]; then
        if ! wp plugin is-active litespeed-cache --allow-root 2>/dev/null; then
            echo "  • Install and activate LiteSpeed Cache plugin" | tee -a "$LOG_FILE"
        fi
        
        if ! wp eval "wp_remote_get('https://api.wordpress.org/core/version-check/1.7/');" --allow-root > /dev/null 2>&1; then
            echo "  • Fix wp_remote_get() SSL certificate issues" | tee -a "$LOG_FILE"
            echo "  • Update CA certificates: update-ca-certificates --fresh" | tee -a "$LOG_FILE"
        fi
    fi
}

# Main execution
echo -e "\n${BLUE}Service Status:${NC}" | tee -a "$LOG_FILE"
check_service "litespeed" "80"
check_service "mysql" "3306"
check_service "redis-server" "6379"
check_service "memcached" "11211"

check_memory
check_cpu
check_disk
check_network
check_cache
check_wordpress
provide_recommendations

echo -e "\n${GREEN}Performance monitoring completed!${NC}" | tee -a "$LOG_FILE"
echo "Full log available at: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
