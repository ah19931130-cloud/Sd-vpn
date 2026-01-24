FROM alpine:latest

# تثبيت xray
RUN apk add --no-cache curl
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip \
    && unzip xray.zip \
    && mv xray /usr/local/bin/xray \
    && chmod +x /usr/local/bin/xray \
    && rm -rf xray.zip

# نسخ الإعدادات
COPY config.json /etc/xray/config.json

# ريندر يعطي منفذ عشوائي عبر المتغير PORT
CMD xray -config /etc/xray/config.json
