echo "==================="
echo "|| DEMO SCENARIO ||"
echo "==================="

echo "\n[E2E streaming data pipeline with client-side field level 🔒 cryptography 🔓 for Apache Kafka Connect and ksqlDB]\n"

echo "-------------------------------------"
echo "step 0: running 🐳 docker containers:"
read -p "-------------------------------------"
docker ps --format '{{.Names}}' | sort

echo "-----------------------------------------"
echo "step 1: 🔎 inspect MongoDB 🍃 {documents}"
read -p "-----------------------------------------"
docker run -it --rm \
        --network sample-scenario \
        mongo:6.0.1 \
        mongosh mongodb:27017/demodb --eval "db.getCollection('fake_citizens').find().limit(10)"

echo "------------------------------------------------------------------------------------------------------------"
echo "step 2a: run kcctl 🧸 to create Debezium MongoDB 🍃 source connector instance using the 🔒 cipherfield SMT 🔒"
read -p "------------------------------------------------------------------------------------------------------------"
docker run -it --rm \
    --network sample-scenario \
    -v ${PWD}/data/connect/:/home \
    debezium/tooling:1.2 \
    bash -c "kcctl config set-context default --cluster=http://connect:8083 && kcctl apply -f /home/register_mongodb_source_k4k_enc.json"

echo "------------------------------------------------------------------"
echo "step 2b: source connector's SMT configuration for 🔒 encryption 🔒"
read -p "------------------------------------------------------------------"
cat data/connect/register_mongodb_source_k4k_enc.json | grep transforms.cipher

echo "-----------------------------------------------------------"
echo "step 3: 🔎 inspect the records written into the kafka topic"
read -p "-----------------------------------------------------------"
docker run --tty --rm \
    --network sample-scenario \
    debezium/tooling:1.2 \
    kafkacat -b kafka:9092 -C -t mongodb.demodb.fake_citizens -o beginning -q | jq .

echo "\n---------------------------------------------------------------------------------------------"
echo "step 4: let's interactively explore the 🔒 field-level cryptography 🔓 UDF support for ksql 🚀"
read -p "---------------------------------------------------------------------------------------------"

docker compose exec ksqldb-cli ksql http://ksqldb-server:8088

echo "-------------------------------------------------------------------------------"
echo "step 5: 🔎 inspect the partially encrypted records written into the kafka topic"
read -p "-------------------------------------------------------------------------------"
docker run --tty --rm \
    --network sample-scenario \
    debezium/tooling:1.2 \
    kafkacat -b kafka:9092 -C -t S_FAKE_CITIZENS_MODIFIED_ENC -o beginning -q | jq .

echo "\n----------------------------------------------------------------------------------------------------"
echo "step 6a: run kcctl 🧸 to create Camel 🐪 minio (s3) 🪣 sink connector using the 🔓 cipherfield SMT 🔓 "
read -p "----------------------------------------------------------------------------------------------------"
docker run -it --rm \
    --network sample-scenario \
    -v ${PWD}/data/connect/:/home \
    debezium/tooling:1.2 \
    bash -c "kcctl config set-context default --cluster=http://connect:8083 && kcctl apply -f /home/register_minio_sink_k4k_dec.json"

echo "----------------------------------------------------------------"
echo "step 6b: sink connector's SMT configuration for 🔓 decryption 🔓"
read -p "----------------------------------------------------------------"
cat data/connect/register_minio_sink_k4k_dec.json | grep transforms.decipher

echo "------------------------------------------------------------------"
echo "step 7: 🔎 inspect the JSON files written into the minio bucket 🪣 "
read -p "------------------------------------------------------------------"

open http://localhost:9001

echo "----------------------------------------------------------------------"
echo "[BONUS] 🐍 Python kafka consumer 🐍 with Kryptonite for Kafka HTTP API"
echo "----------------------------------------------------------------------"

echo "\n----------------------------------------------------------------------------------------------------"
read -p "read kafka topic data and decrypt SMT encrypted data with python kafka consumer"

docker run  -e bootstrap_servers=kafka:9092 -e kryptonite_cipher_mode=decrypt -e kryptonite_kafka_topic=mongodb.demodb.fake_citizens -e kryptonite_field_config='[ { "name": "personal", "fieldMode": "ELEMENT" }, { "name": "personal.lastname" }, { "name": "personal.age" }, { "name": "personal.eyecolor" }, { "name": "personal.height" }, { "name": "personal.weight" }, { "name": "contact", "fieldMode": "OBJECT" }, { "name": "knownresidences", "fieldMode": "ELEMENT" } ]' -it --rm --network=sample-scenario python-demo/kryptonite-http-api:0.1.0

echo "\n----------------------------------------------------------------------------------------------------"
read -p "read kafka topic data and decrypt UDF encrypted data with python kafka consumer"

docker run  -e bootstrap_servers=kafka:9092 -e kryptonite_cipher_mode=decrypt -e kryptonite_kafka_topic=S_FAKE_CITIZENS_MODIFIED_ENC -e kryptonite_field_config='[ { "name": "FULLNAME" }, { "name": "PHONE" }, { "name": "ADDRESSES", "fieldMode":"ELEMENT" } ]' -it --rm --network=sample-scenario python-demo/kryptonite-http-api:0.1.0

echo "\n\n🙇‍♂️ THANKS for your attention ... and for sending prayers 🙏\n"

read -p "? SHUTDOWN docker containers ?"

docker compose down

echo "👋 bye bye 👋"
