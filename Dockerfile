FROM alpine:3.24 AS nginx_build
RUN apk add --no-cache build-base curl perl pcre2-dev openssl-dev zlib-dev linux-headers patch
WORKDIR /src
RUN curl -fsSL --retry 3 https://openresty.org/download/openresty-1.31.8.1.tar.gz -o openresty.tar.gz \
    && echo 'b569c63b420f80a4ac8466f2deffe73ed93ab760026532e039c3658409a997f4  openresty.tar.gz' | sha256sum -c - \
    && tar -xzf openresty.tar.gz
COPY nginx/patches/nginx-1.31.9-security.patch /src/nginx-security.patch
RUN cd openresty-1.31.8.1/bundle \
    && patch --batch --fuzz=0 -p0 < /src/nginx-security.patch \
    && sed -i 's/#define nginx_version      1031008/#define nginx_version      1031009/' nginx-1.31.8/src/core/nginx.h \
    && sed -i 's/#define NGINX_VERSION      "1.31.8"/#define NGINX_VERSION      "1.31.9"/' nginx-1.31.8/src/core/nginx.h \
    && sed -i 's/NGINX_VERSION "\.1"/NGINX_VERSION ".1-hanasand1"/' nginx-1.31.8/src/core/nginx.h \
    && grep -q 'NGINX_VERSION      "1.31.9"' nginx-1.31.8/src/core/nginx.h
RUN cd openresty-1.31.8.1 \
    && ./configure --with-pcre-jit --with-compat --with-threads \
       --with-http_ssl_module --with-http_v2_module \
       --with-http_realip_module --with-http_auth_request_module \
       --with-http_stub_status_module --with-http_gzip_static_module \
       --with-http_sub_module --with-http_slice_module \
       --with-http_dav_module --with-http_secure_link_module \
       --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module \
    && make -j4 \
    && make install

FROM openresty/openresty:1.31.8.1-alpine
COPY --from=nginx_build /usr/local/openresty /usr/local/openresty

RUN apk add --no-cache curl perl python3 py3-pip openssl pcre2 libgcc libstdc++ zlib \
    && python3 -m venv /opt/certbot \
    && /opt/certbot/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/certbot/bin/pip install --no-cache-dir certbot certbot-dns-domeneshop \
    && ln -s /opt/certbot/bin/certbot /usr/local/bin/certbot \
    && opm get ledgetech/lua-resty-http \
    && mkdir -p /var/log/nginx
