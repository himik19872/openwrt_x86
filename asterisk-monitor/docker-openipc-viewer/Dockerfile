FROM mcr.microsoft.com/dotnet/runtime:8.0-jammy

WORKDIR /app

# Копируем бинарники OpenIPC viewer
COPY OpenIPC.Viewer.Desktop .
COPY appsettings.json .
COPY runtimes/ runtimes/

# ffmpeg
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

EXPOSE 8787

ENV OPENIPC_WEB_ADMIN_PASSWORD=asterisk123

ENTRYPOINT ["/app/OpenIPC.Viewer.Desktop", "--server-only", "--lan", "--port", "8787"]
