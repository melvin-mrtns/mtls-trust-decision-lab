.PHONY: regen certs success-run clean root intermediate server client

regen: clean root intermediate server client

certs: root intermediate server client

success-run: certs
	chmod +x client/curl.sh
	chmod +x client/success-run.sh
	./client/success-run.sh

clean:
	rm -f certs/root/*.crt certs/root/*.key certs/root/*.srl certs/root/*.csr
	rm -f certs/ca/*.crt
	rm -f certs/intermediate/*.crt certs/intermediate/*.key certs/intermediate/*.csr certs/intermediate/*.srl
	rm -f certs/server/*.crt certs/server/*.key certs/server/*.csr certs/server/*.srl
	rm -f certs/client/*.crt certs/client/*.key certs/client/*.csr certs/client/*.srl

root:
	openssl genrsa -out certs/root/root.key 4096
	openssl req -new -sha256 \
      -key certs/root/root.key \
      -subj "/C=US/O=Lab Root CA/CN=Lab Root CA" \
      -out certs/root/root.csr
	openssl x509 -req -sha256 \
		-in certs/root/root.csr \
		-signkey certs/root/root.key \
		-days 3650 \
		-out certs/root/root.crt \
		-extfile certs/root/root.ext \
		-extensions v3_root_ca
	cp certs/root/root.crt certs/ca/

intermediate: root
	openssl genrsa -out certs/intermediate/intermediate.key 4096
	openssl req -new -sha256 \
	  -key certs/intermediate/intermediate.key \
	  -subj "/C=US/O=Lab Intermediate CA/CN=Lab Intermediate CA" \
	  -out certs/intermediate/intermediate.csr
	openssl x509 -req -sha256 \
	  -in certs/intermediate/intermediate.csr \
	  -CA certs/root/root.crt \
	  -CAkey certs/root/root.key \
	  -CAcreateserial \
	  -days 1825 \
	  -out certs/intermediate/intermediate.crt \
	  -extfile certs/intermediate/intermediate.ext \
	  -extensions v3_intermediate_ca

server: intermediate
	openssl genrsa -out certs/server/server.key 2048
	openssl req -new -sha256 \
	  -key certs/server/server.key \
	  -subj "/C=US/O=Lab Server/CN=localhost" \
	  -out certs/server/server.csr
	openssl x509 -req -sha256 \
	  -in certs/server/server.csr \
	  -CA certs/intermediate/intermediate.crt \
	  -CAkey certs/intermediate/intermediate.key \
	  -CAcreateserial \
	  -days 120 \
	  -out certs/server/server.crt \
	  -extfile certs/server/server.ext \
	  -extensions v3_server

client: intermediate
	openssl genrsa -out certs/client/client.key 2048
	openssl req -new -sha256 \
	  -key certs/client/client.key \
	  -subj "/C=US/O=Lab Client/CN=lab-client" \
	  -out certs/client/client.csr
	openssl x509 -req -sha256 \
	  -in certs/client/client.csr \
	  -CA certs/intermediate/intermediate.crt \
	  -CAkey certs/intermediate/intermediate.key \
	  -CAcreateserial \
	  -days 120 \
	  -out certs/client/client.crt \
	  -extfile certs/client/client.ext \
	  -extensions v3_client
