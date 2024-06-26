# Base image for building
ARG LITELLM_BUILD_IMAGE=python:3.11.8-slim

# Runtime image
ARG LITELLM_RUNTIME_IMAGE=python:3.11.8-slim

# Builder stage
FROM $LITELLM_BUILD_IMAGE as builder

# Creat
USER 15006

USER root
# Set the working directory to /app
WORKDIR /app

# Install build dependencies
RUN apt-get clean && apt-get update && \
    apt-get install -y gcc python3-dev nodejs npm && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip && \
    pip install build

# Copy the current directory contents into the container at /app
COPY . .

# Build Admin UI (run as root)
RUN chmod +x build_admin_ui.sh && ./build_admin_ui.sh

# Build the package (run as root)
RUN rm -rf dist/* && python -m build

# There should be only one wheel file now, assume the build only creates one
RUN ls -1 dist/*.whl | head -1

# Install the package (run as root)
RUN pip install dist/*.whl

# install dependencies as wheels (run as root)
RUN pip wheel --no-cache-dir --wheel-dir=/wheels/ -r requirements.txt

# install semantic-cache [Experimental]- we need this here and not in requirements.txt because redisvl pins to pydantic 1.0 (run as root)
RUN pip install redisvl==0.0.7 --no-deps

# ensure pyjwt is used, not jwt (run as root)
RUN pip uninstall jwt -y
RUN pip uninstall PyJWT -y
RUN pip install PyJWT --no-cache-dir

# Build Admin UI (run as root)
RUN chmod +x build_admin_ui.sh && ./build_admin_ui.sh

# Give all permissions to the user (run as root)
RUN chown -R 15006:15006 /app
RUN npm install -g prisma
# Switch to the user
USER 15006

# Generate prisma client
RUN prisma generate

# Make entrypoint executable
RUN chmod +x entrypoint.sh

# Runtime stage
FROM $LITELLM_RUNTIME_IMAGE as runtime

# Create the user (already done in the builder stage)
# RUN adduser --disabled-password --gecos "" litellm

# Set the working directory to /app
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . .
RUN ls -la /app

# Copy the built wheel from the builder stage to the runtime stage; assumes only one wheel file is present
COPY --from=builder /app/dist/*.whl .
COPY --from=builder /wheels/ /wheels/

# Install the built wheel using pip; again using a wildcard if it's the only file
RUN pip install *.whl /wheels/* --no-index --find-links=/wheels/ && rm -f *.whl && rm -rf /wheels

# Switch to the user
USER 15006

# Ensure user has permissions to run litellm
RUN chmod +x 15006

EXPOSE 4000/tcp

ENTRYPOINT ["litellm"]

# Append "--detailed_debug" to the end of CMD to view detailed debug logs 
CMD ["--port", "4000"]
