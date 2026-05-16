# ─────────────────────────────────────────────
# STAGE 1 — Build
# ─────────────────────────────────────────────
FROM node:20-alpine AS builder


WORKDIR /app

COPY package*.json ./


RUN npm ci

COPY . .

# Variables de entorno en tiempo de build (sobreescribibles con --build-arg)
ARG VITE_API_URL=http://localhost:8080
ENV VITE_API_URL=${VITE_API_URL}


RUN npm run build

# ─────────────────────────────────────────────
# STAGE 2 — Serve (imagen mínima con nginx)
# ─────────────────────────────────────────────
FROM nginx:1.27-alpine AS production

RUN rm -rf /usr/share/nginx/html/*

# Copiar el build generado en el stage anterior
COPY --from=builder /app/dist /usr/share/nginx/html

# Copia configuración personalizada de nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Usuario no root: nginx ya corre como usuario "nginx" en alpine
# dar permisos adecuados
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && chmod -R 755 /etc/nginx/conf.d/ \
    && touch /var/run/nginx.pid \
    && chown nginx:nginx /var/run/nginx.pid

USER nginx


EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080 || exit 1

CMD ["nginx", "-g", "daemon off;"]
