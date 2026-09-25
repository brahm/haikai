FROM php:8.3-apache
RUN apt-get update && apt-get install -y --no-install-recommends libicu-dev \
 && docker-php-ext-install mysqli intl && a2enmod rewrite && rm -rf /var/lib/apt/lists/*
RUN sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf
