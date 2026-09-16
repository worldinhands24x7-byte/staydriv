# Production Stage for StayDriv Backend & Web Client
FROM node:20-alpine

# Set working directory
WORKDIR /usr/src/app

# Copy package dependencies
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production

# Copy server files and compiled public web assets
COPY server.js ./
COPY public/ ./public/

# Expose backend port
EXPOSE 3000

# Define env variables defaults
ENV PORT=3000
ENV NODE_ENV=production

# Start Node server
CMD [ "node", "server.js" ]
