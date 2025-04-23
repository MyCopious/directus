# syntax=docker/dockerfile:1.4

ARG NODE_VERSION=22

####################################################################################################
## Build Packages

FROM node:${NODE_VERSION}-alpine AS builder

# Remove again once corepack >= 0.31 made it into base image
# (see https://github.com/directus/directus/issues/24514)
RUN npm install --global corepack@latest

RUN apk --no-cache add python3 py3-setuptools build-base

WORKDIR /directus

COPY package.json .
RUN corepack enable && corepack prepare

# Deploy as 'node' user to match pnpm setups in production image
# (see https://github.com/directus/directus/issues/23822)
RUN chown node:node .
USER node

ENV NODE_OPTIONS=--max-old-space-size=8192

COPY pnpm-lock.yaml .
RUN pnpm fetch

COPY --chown=node:node . .
RUN <<EOF
	set -ex
	pnpm install --recursive --offline --frozen-lockfile
	npm_config_workspace_concurrency=1 pnpm run build
	pnpm --filter directus deploy --prod dist
	cd dist
	# Regenerate package.json file with essential fields only
	# (see https://github.com/directus/directus/issues/20338)
	node -e '
		const f = "package.json", {name, version, type, exports, bin} = require(`./${f}`), {packageManager} = require(`../${f}`);
		fs.writeFileSync(f, JSON.stringify({name, version, type, exports, bin, packageManager}, null, 2));
	'
	mkdir -p database extensions uploads
EOF

####################################################################################################
## Include Custom Extensions

# Build and copy get_env extension
WORKDIR /directus/api/extensions/get_env
RUN <<EOF
	npm install
	npm run build
	# Create extension directory with proper Directus naming convention
	mkdir -p /directus/built-extensions/get_env
	# Copy both the dist directory and package.json
	cp -r dist /directus/built-extensions/get_env/
	cp package.json /directus/built-extensions/get_env/
EOF

####################################################################################################
## Create Production Image

FROM node:${NODE_VERSION}-alpine AS runtime

RUN npm install --global \
	pm2@5 \
	corepack@latest # Remove again once corepack >= 0.31 made it into base image

USER node

WORKDIR /directus

ENV \
	DB_CLIENT="sqlite3" \
	DB_FILENAME="/directus/database/database.sqlite" \
	NODE_ENV="production" \
	NPM_CONFIG_UPDATE_NOTIFIER="false"

COPY --from=builder --chown=node:node /directus/ecosystem.config.cjs .
COPY --from=builder --chown=node:node /directus/dist .
COPY --from=builder --chown=node:node /directus/built-extensions /directus/built-extensions

# Create entrypoint script to copy extensions on startup
USER root
RUN <<EOF
	cat > /entrypoint.sh << 'EOT'
#!/bin/sh
if [ -d "/directus/built-extensions" ]; then
  mkdir -p /directus/extensions
  cp -r /directus/built-extensions/* /directus/extensions/
  echo "Copied built-in extensions to /directus/extensions"
fi
exec "$@"
EOT
	chmod +x /entrypoint.sh
EOF
USER node

EXPOSE 8055

ENTRYPOINT ["/entrypoint.sh"]
CMD : \
	&& node cli.js bootstrap \
	&& pm2-runtime start ecosystem.config.cjs \
	;
