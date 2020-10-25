#############################
#     设置公共的变量        #
#############################
FROM php:fpm-alpine as base
# 作者描述信息
MAINTAINER danxiaonuo
# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ

# 镜像变量
ARG DOCKER_IMAGE=danxiaonuo/php
ENV DOCKER_IMAGE=$DOCKER_IMAGE
ARG DOCKER_IMAGE_OS=php
ENV DOCKER_IMAGE_OS=$DOCKER_IMAGE_OS
ARG DOCKER_IMAGE_TAG=fpm-alpine
ENV DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG
ARG BUILD_DATE
ENV BUILD_DATE=$BUILD_DATE
ARG VCS_REF
ENV VCS_REF=$VCS_REF

# ##############################################################################

# ***** 设置变量 *****

# dumb-init
# https://github.com/Yelp/dumb-init
ARG DUMBINIT_VERSION=1.2.2
ENV DUMBINIT_VERSION=$DUMBINIT_VERSION

# 构建安装依赖
ARG BUILD_DEPS="\
      cyrus-sasl-dev \
      git \
      autoconf \
      g++ \
      libtool \
      make \
      libgcrypt \
      pcre-dev"
ENV BUILD_DEPS=$BUILD_DEPS

# 构建安装依赖
ARG PHP_BUILD_DEPS="\
      tzdata \
      tini \
      libintl \
      icu \
      icu-dev \
      libxml2-dev \
      postgresql-dev \
      freetype-dev \
      libjpeg-turbo-dev \
      libpng-dev \
      gmp \
      gmp-dev \
      libmemcached-dev \
      imagemagick-dev \
      libzip-dev \
      zlib-dev \
      libssh2-dev \
      libwebp-dev \
      libxpm-dev \
      libvpx-dev \
      libxslt-dev \
      libmcrypt-dev"
ENV PHP_BUILD_DEPS=$PHP_BUILD_DEPS

####################################
#       构建扩展插件PHP            #
####################################
FROM base AS builder

# http://label-schema.org/rc1/
LABEL maintainer="danxiaonuo <danxiaonuo@danxiaonuo.me>" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="$DOCKER_IMAGE" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.url="https://github.com/$DOCKER_IMAGE" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/$DOCKER_IMAGE" \
      org.label-schema.version="$NGINX_VERSION-$DOCKER_IMAGE_OS$DOCKER_IMAGE_TAG" \
      versions.dumb-init=${DUMBINIT_VERSION}


# 修改源地址
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
# ***** 安装相关依赖并更新系统软件 *****
# ***** 安装依赖 *****
RUN set -eux \
   # 更新源地址
   && apk update \
   # 更新系统并更新系统软件
   && apk upgrade && apk upgrade \
   && apk add -U --update --virtual .$BUILD_DEPS \
   && apk add -U --update $PHP_BUILD_DEPS \
   # 更新时区
   && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
   # 更新时间
   && echo ${TZ} > /etc/timezone
# ##############################################################################
# ***** 安装扩展插件 *****
# Composer安装
RUN curl -sS https://getcomposer.org/installer | php  && \
mv composer.phar /usr/local/bin/composer              &&  \
composer self-update --clean-backups
# xhprof github上下载支持php7的扩展 安装 开启扩展
RUN git clone https://github.com/longxinH/xhprof.git /tmp/xhprof \
    && ( \
        cd /tmp/xhprof/extension \
        && phpize \
        && ./configure  \
        && make -j$(nproc) \
        && make install \
    ) \
    && rm -r /tmp/xhprof \
    && docker-php-ext-enable xhprof
# 安装内置扩展
RUN docker-php-source extract && \
# 安装redis扩展
git clone https://github.com/phpredis/phpredis.git /usr/src/php/ext/redis    && \
# 安装memcached扩展
git clone https://github.com/php-memcached-dev/php-memcached.git /usr/src/php/ext/memcached/    && \
docker-php-ext-configure memcached      &&  \
docker-php-ext-configure exif           && \
docker-php-ext-configure gd               \
      --with-freetype=/usr/include/       \
      --with-xpm=/usr/include/            \
      --with-webp=/usr/include/           \
      --with-jpeg=/usr/include/        && \
# 安装php扩展插件
docker-php-ext-install -j "$(nproc)"                    \
    intl                                                \
    bcmath                                              \
    zip                                                 \
    soap                                                \
    mysqli                                              \
    pdo                                                 \
    pdo_mysql                                           \
    pdo_pgsql                                           \
    gmp                                                 \
    redis                                               \
    iconv                                               \
    gd                                                  \
    memcached                                       &&  \
docker-php-ext-configure opcache --enable-opcache           &&  \
docker-php-ext-install opcache                              &&  \
docker-php-ext-install exif                                 &&  \
pecl install apcu imagick msgpack mongodb  swoole           &&  \
docker-php-ext-enable apcu imagick msgpack mongodb swoole   &&  \          
apk del .$BUILD_DEPS                                        &&  \
docker-php-source delete                                    &&  \
rm -rf /tmp/* /var/cache/apk/*                              &&  \
# 安装dumb-init
curl -Lo /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_x86_64 && \
chmod +x /usr/bin/dumb-init

# 拷贝配置文件
COPY conf/php/php.production.ini /usr/local/etc/php/php.ini
COPY conf/php/docker-php.ini /usr/local/etc/php/docker-php.ini
COPY conf/php/zz-docker.production.conf /usr/local/etc/php-fpm.d/zz-docker.conf

# 容器信号处理
STOPSIGNAL SIGQUIT

# 入口
ENTRYPOINT ["dumb-init"]

# 启动命令
CMD ["php-fpm"]