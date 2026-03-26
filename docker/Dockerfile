FROM node:22-slim
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN npm install -g openclaw@latest
ENV HOME=/home/openclaw
WORKDIR /home/openclaw
CMD ["openclaw", "gateway", "--port", "18789"]
