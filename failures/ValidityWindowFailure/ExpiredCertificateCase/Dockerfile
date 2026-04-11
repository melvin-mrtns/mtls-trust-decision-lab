FROM nginx:stable
RUN apt-get update \
 && apt-get install -y --no-install-recommends libfaketime \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf /usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 /usr/lib/libfaketime.so.1